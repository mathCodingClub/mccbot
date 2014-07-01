use Irssi;
use lib 'modules';

use URI::Escape;
use strict;

our %global;
our %msg_buffer;

sub clean_eval {
    return eval shift;
}

my $char   = '!';
my $charre = quotemeta $char;

my $commands = 'commands';

sub reply { $_{server}->command("msg $_{target} $_{nick}: $_") for @_ }
sub say   { $_{server}->command("msg $_{target} $_") for @_ }
sub reply_private   { $_{server}->command("msg $_{nick} $_") for @_ }
sub match { $_{server}->masks_match("@_", $_{nick}, $_{address}) }

sub load {
          my ($command, $server, $nick, $target) = @_;
    my $mtime =  (stat "$commands/$command")[9];
    if ($mtime) {
        if ($mtime > $global{filecache}{$command}{mtime}) {
            local $/ = undef;
            open my $fh, "$commands/$command"; # no die
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

    $msg =~ s/(\".*?\")/uri_escape($1)/ge;

    my $path = $rest . "/" . $command . "/" . $msg;

    $path =~ s/ /\//g;

    Irssi::print $path;

    my $gotinfo = `curl -s $path`;

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
          'foreach(@lines)',
          '{',
            'say($_);',
          '}',
        '}';

      eval {
        $code->( {
            server => $server,
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
  push(@{$msg_buffer{$target}}, "{\"user\":\"$nick\",\"quote\":\"$msg\"}");
}

our $last_msg = "";

sub message {
    my ($server, $msg, $nick, $address, $target) = @_;

    if($last_msg eq "")
    {
      $last_msg = $msg;

      if( ($nick ne "mccbot") && (not $last_msg =~ m/^$charre(\w+)(?:$| )/) && $target ne $nick)
      {
        push_to_buffer($last_msg, $nick, $target);
      }
      
    }

    return $last_msg = "" unless $msg =~ s/^$charre(\w+)(?:$| )//;
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
      $_[1] = "\cO" . $_[1];
      Irssi::signal_emit($target ? 'message public' : 'message private', @_);

      $target ||= $nick;
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

    Irssi::print $@ if $@;
    Irssi::signal_stop;
    $last_msg = "";
}

Irssi::signal_add_last 'message public' => \&message;
Irssi::signal_add_last 'message private' => \&message;

load '=init';
