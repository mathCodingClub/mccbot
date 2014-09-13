use Irssi;
use lib 'modules';

use URI::Escape;
use URI::Find;

use strict;

our %global;
our %msg_buffer;

Irssi::print(`pwd`);

our @uris;
our $finder = URI::Find->new(sub
{
  my($uri) = shift;
  push @uris, $uri;  
});

sub clean_eval {
    return eval shift;
}

my $char   = '!';
my $charre = quotemeta $char;

my $commands = 'commands';
my $irssi_config = '/home/acce/.mccbot';

sub reply { $_{server}->command("msg $_{target} $_{nick}: $_") for @_ }
sub say   { $_{server}->command("msg $_{target} $_") for @_ }
sub reply_private   { $_{server}->command("msg $_{nick} $_") for @_ }
sub match { $_{server}->masks_match("@_", $_{nick}, $_{address}) }

sub load {
          my ($command, $server, $nick, $target) = @_;
    my $mtime =  (stat "$irssi_config/$commands/$command")[9];
    if ($mtime) {
        if ($mtime > $global{filecache}{$command}{mtime}) {
            local $/ = undef;
            open my $fh, "$irssi_config/$commands/$command"; # no die
            $global{filecache}{$command} = {
                mtime => $mtime,
                code  => clean_eval join "\n", 
                    'sub {',
                        'local %_ = %{ +shift };',
                        "#line 1 $command",
                        readline($fh),
                    '}'
            };
            Irssi::print $@ ? $@ : "Loaded $command";
        }
        return $global{filecache}{$command}{code};
    }

    Irssi::print "Could not load $command";
    delete $global{filecache}{$command} if exists $global{filecache}{$command};
    return undef;
}

sub try_rest
{
    my ($server, $command, $msg, $nick, $target) = @_;

    my $rest = "http://rest.localhost";

    my $method = "GET";
    my $data = "";

    if($msg =~ s/^://)
    {
      $method = uc($command);
      if(not $method =~ m/POST|GET|OPTIONS|DELETE|PUT/)
      {
	$server->command("msg $target $nick: Invalid HTTP method!");
        return 0;
      }
      else
      {
        $command = "";


        if($method eq "POST")
        {
          $msg =~ s/(\{.*?\})//;
          my $d = $1;
          if($d eq "")
          {
            $server->command("msg $target $nick: No post data given! Use wave brackets to enclose data, the brackets are included to the data (eg. !post:command pathparam {postdata})");
            return 0;
          }
          else
          {
            $msg =~ s/^\s+|\s+$//g;
            $data = "-d \'$d\'";
          }
        }
      }
    }

    $command =~ s/^\s+|\s+$//g;
    $msg =~ s/\"(.*?)\"/uri_escape($1)/ge;
    my $path = $rest . "/" . $command;
    if($msg ne "")
    {
     $path .= "/" . $msg;   
   
     $path =~ s/^\s+|\s+$//g;
     $path =~ s/\s/\//g;
     $path =~ s/\/$/\//g;

    }


    Irssi::print "method: " . $method . ", path: " . $path . ", data: " . $data;

    my $gotinfo = `curl -s -X $method $data $path`;

    if(index($gotinfo, "404 Page Not Found") != -1)
    {
      return 0; #command not found in rest either
    }
    else
    {
      my $code = eval join "\n",
        'sub {',
          'local %_ = %{ +shift @_ };',
          'my @lines = split(/\n/, $gotinfo);',
          'my $sender = \&say;',
          'if(scalar @lines > 4)',
          '{',
          '$sender = \&reply_private;',
          '',
          '}',
          'foreach(@lines)',
          '{',
            '$sender->($_);',
          '}',
        '}';

      $target ||= $nick;
      eval {
        $code->( {
            server => $server,
            nick => $nick,
            target => $target
        });
      };
      return 1;
    }

}

sub push_to_buffer
{
  my ($msg, $nick, $target) = @_;

  if(not defined @{$msg_buffer{$target}})
  {
    @{$msg_buffer{$target}} = [];
  }

  if(scalar @{$msg_buffer{$target}} > 15)
  {
    shift @{$msg_buffer{$target}};
  }
  $msg =~ s/"/\\"/g;
  push(@{$msg_buffer{$target}}, "{\"user\":\"$nick\",\"quote\":\"$msg\"}");
}

sub send_titles_for_url
{
  my ($server, $msg, $nick, $target) = @_;

  $finder->find(\$msg);

  foreach(@uris)
  {
    my $title = `curl -s $_`;
    $title =~ s/.*?<title>(.*?)<\/title>.*?//;
    if( $1 ne "")
    {
      $server->command("msg $target Title - $1");
    }
  }

  @uris=();

}

our $last_msg = "";

sub message {
    my ($server, $msg, $nick, $address, $target) = @_;

    send_titles_for_url($server, $msg, $nick, $target);

    if($last_msg eq "")
    {
      $last_msg = $msg;

      if( ($nick ne "mccbot") && (not $last_msg =~ m/^$charre(\w+)(?:$| )/) && $target ne $nick)
      {
        push_to_buffer($last_msg, $nick, $target);
      }
      
    }

    return $last_msg = "" unless $msg =~ s/^$charre(\w+)\s*//;
    my $command = $1;
 
    my $code = load($command);
    if (not ref $code)
    {
        $last_msg = "";
	my $rest_success = try_rest($server, $command, $msg, $nick, $target);
	return $server->command("msg $target $nick: I don't know that command!") if not $rest_success;
    }
    else
    {    


      eval {

        $code->( {
            command => "$char$command",
            server  => $server,
            msg     => $msg,
            nick    => $nick, 
            address => $address,
            target  => $target
        } );

      };
    }
    Irssi::print "$command by $nick${\ ($target ? qq/ in $target/ : '') } on " .
                 "$server->{address}";

    $_[1] = "\cO" . $_[1];
    $target ||= $nick;

    Irssi::signal_emit($target ? 'message public' : 'message private', @_);

    Irssi::print $@ if $@;
    Irssi::signal_stop;
    $last_msg = "";
}

Irssi::signal_add_last 'message public' => \&message;
Irssi::signal_add_last 'message private' => \&message;

load '=init';
