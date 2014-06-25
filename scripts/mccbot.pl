use Irssi;
use lib 'module';
use strict;

our %global;

sub clean_eval {
    return eval shift;
}

my $char   = '!';
my $charre = quotemeta $char;

my $commands = 'commands';

sub reply { $_{server}->command("msg $_{target} $_{nick}: $_") for @_ }
sub reply_all { $_{server}->command("msg $_{target} $_") for @_ }
sub say   { $_{server}->command("msg $_{target} $_") for @_ }
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
    $server->command("msg $target $nick: I don't know that command!");
    delete $global{filecache}{$command} if exists $global{filecache}{$command};
    return undef;
}

sub message {
    my ($server, $msg, $nick, $address, $target) = @_;
    return unless $msg =~ s/^$charre(\w+)(?:$| )//;
    my $command = $1;
 
    my $code = load($command, $server, $nick, $target);
    return if not ref $code;
    Irssi::print "$command by $nick${\ ($target ? qq/ in $target/ : '') } on " .
                 "$server->{address}";
    
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
    Irssi::print $@ if $@;
    Irssi::signal_stop;
}

Irssi::signal_add_last 'message public' => \&message;
Irssi::signal_add_last 'message private' => \&message;

load '=init';
