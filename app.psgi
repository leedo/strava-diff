#!/usr/bin/env perl

use JSON::XS;
use Data::Dump qw{pp};
use Text::Xslate;
use Plack::Request;
use Plack::Builder;
use Plack::Session;
use Router::Simple;
use StravaDiff;

my ($client_id, $client_secret) = do {
  open my $fh, "<", ($ENV{STRAVA_SECRET} || "strava_secret")
    or die "missing strava secrets";
  split " ", <$fh>;
};

my $tx = Text::Xslate->new(
  path => "./share/templates",
  function => {
    minutes => sub { int($_[0] / 60) . "m" }
  }
);

my $router = Router::Simple->new;
$router->connect("/activity/{id}", {action => "activity"}, {method => "GET"});
$router->connect("/diff/{a}/{b}", {action => "diff"}, {method => "GET"});

builder {
  enable "Static", path => qr{^/assets/}, root => "./share";
  enable "Session::Cookie", secret => $client_secret;

  sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $strava = StravaDiff->new(
      $client_id, $client_secret,
      $env->{"psgix.session"}{token}
    );

    if ($req->path_info eq "/authorize") {
      if (my $token = $strava->oauth_complete($req->parameters->{code})) {
        $env->{"psgix.session"}{token} = $token;
        return [301, [qw{Location /}], ["redirecting"]]
      }
      return [
        500,
        [qw{Content-Type text/html}],
        [$tx->render("error.tx", {error => "Failed to get authorization from Strava."})]
      ];
    }

    return [301, [Location => $strava->oauth_url], ["redirecting"]]
      unless $strava->can_read;

    if ($req->path_info eq "/") {
      return [
        200,
        [qw{Content-Type text/html}],
        [$tx->render("index.tx", {strava => $strava})]
      ];
    }

    if (my $match = $router->match($env)) {
      my $action = delete $match->{action};
      if ($strava->can($action)) {
        my $html = $tx->render("$action.tx", {$action => $strava->$action(%$match)});
        return [200, [qw{Content-Type text/html}], [$html]];
      }
    }

    return [404, [qw{Content-Type text/plain}], ["not found"]];
  };
};
