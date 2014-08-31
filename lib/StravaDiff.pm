package StravaDiff;

use feature "signatures";
use List::MoreUtils qw{any};
use List::Util qw{first};
use HTTP::Tiny;
use JSON::XS;
use Data::Dump qw{pp};
use URI;
use URI::QueryParam;
use Redis;

sub new ($class, $id, $secret, $token) {
  bless {
    token => $token,
    base => "https://www.strava.com",
    client => {
      id => $id,
      secret => $secret,
    },
  }, $class;
}

sub can_read ($self) {
  defined $self->{token};
}

sub oauth_url ($self, $return) {
  my $uri = URI->new("$self->{base}/oauth/authorize");
  $uri->query_form_hash({
    client_id => $self->{client}{id},
    redirect_uri => $return,
    response_type => "code",
  });
  $uri->as_string;
}

sub oauth_complete ($self, $code) {
  my $client = HTTP::Tiny->new;
  my $res = $client->post_form("$self->{base}/oauth/token", {
    client_id => $self->{client}{id},
    client_secret => $self->{client}{secret},
    code => $code,
  });

  if ($res->{success}) {
    my $data = decode_json $res->{content};
    return $data->{access_token};
  }
}

sub activities ($self) {
  my $res = $self->api_request(get => "activities");
}

sub activity ($self, %args) {
  $self->api_request(get => "activities/$args{id}");
}

sub diff ($self, %args) {
  my $a = $self->activity(id => $args{a});
  my $b = $self->activity(id => $args{b});
  my @efforts;

  for my $effort (@{$a->{segment_efforts}}) {
    my $match = first {$_->{segment}{id} == $effort->{segment}{id}} @{$b->{segment_efforts}};
    if ($match) {
      my $change = $effort->{elapsed_time} - $match->{elapsed_time};
      push @efforts, {
        effort => $effort,
        change => $change,
        class => $change == 0 ? "same" : $change > 0 ? "worse" : "improved",
      };
    }
    else {
      push @efforts, {
        effort => $effort,
        class => "added",
      };
    }
  }

  for my $i (0 .. @{$b->{segment_efforts}} - 1) {
    my $effort = $b->{segment_efforts}[$i];
    next if any {$_->{segment}{id} == $effort->{segment}{id}} @{$a->{segment_efforts}};
    @efforts = (@efforts[0 .. $i], {
      effort => $effort,
      class => "removed",
    }, @efforts[$i + 1 .. $#efforts]);
  }

  return {
    a => $a,
    b => $b,
    segments => \@efforts
  };
}

sub api_request ($self, $meth, $path, %query) {
  my $redis = Redis->new;
  my $key = join ":", $meth, $path, sort %query;
  my $json = $redis->get($key);
  if (!$json) {
    my $client = HTTP::Tiny->new;
    my $res = $client->$meth("$self->{base}/api/v3/$path", {
      headers => { Authorization => "Bearer $self->{token}"}
    });
    $json = $res->{content};
    $redis->setex($key, 300, $json);
  }
  return decode_json $json;
}

1;
