package StravaDiff;

use feature "signatures";
use HTTP::Tiny;
use JSON::XS;
use Data::Dump qw{pp};
use URI;
use URI::QueryParam;

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

sub oauth_url ($self) {
  my $uri = URI->new("$self->{base}/oauth/authorize");
  $uri->query_form_hash({
    client_id => $self->{client}{id},
    redirect_uri => "http://127.0.0.1:5000/authorize",
    response_type => "code"
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
  my %diff;

  for my $effort (@{$a->{segment_efforts}}) {
    for my $search (@{$b->{segment_efforts}}) {
      if ($search->{segment}{id} == $effort->{segment}{id}) {
        $diff{$effort->{id}} = $effort->{elapsed_time} - $search->{elapsed_time};
      }
    }
  }

  return {
    a => $a,
    b => $b,
    diff => \%diff
  };
}

sub api_request ($self, $meth, $path, %query) {
  my $client = HTTP::Tiny->new;
  my $res = $client->$meth("$self->{base}/api/v3/$path", {
    headers => { Authorization => "Bearer $self->{token}"}
  });
  return decode_json $res->{content};
}

1;
