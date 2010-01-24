use v6;
use Test;
use GGE;

my %cached;

sub dirname($path) { $path.comb(/<-[/]>+ '/'/).join() } #' (vim fix)

my @test-files = <
    metachars
    quantifiers
    backtrack
    charclass
    modifiers
    captures
    subrules
>;

for @test-files -> $test-file {
    my Str $filename = dirname($*PROGRAM_NAME) ~ 'rx_' ~ $test-file;
    my IO $fh = open $filename, :r;
    my Int $i = 0;
    for $fh.lines -> $line {
        next if $line eq '';
        if $line ~~ /^ \# \s* todo \s* (.*) $/ {
            my $reason = $0;
            todo($reason);
        }
        next if $line ~~ /^ \#/;
        $i++;
        $line ~~ /^ (<-[\t]>*) \t+ (<-[\t]>+) \t+ (<-[\t]>+) \t+ (.*) $/
            or die "Unrecognized line format: $line";
        my ($pattern, $target, $result, $description) = $0, $1, $2, $3;
        $target  = $target eq q[''] ?? '' !! backslash_escape($target);
        $result  = backslash_escape($result);
        my $full-description = "[$test-file:$i] $description";
        my $match;
        my $failed = 1; # RAKUDO: Manual CATCH workaround
        try {
            $match = match_perl6regex($pattern, $target);
            $failed = 0;
        }
        if $failed {
            if $result eq 'y'|'n' {
                nok 1, $full-description;
            }
            else {
                $result .= substr(1,-1); # remove /'s
                ok defined((~$!).index($result)), $full-description;
            }
        }
        elsif $result eq 'y' {
            ok ?$match, $full-description;
        }
        elsif $result eq 'n' {
            ok !$match, $full-description;
        }
        else {
            $result .= substr(1,-1); # remove /'s
            ok defined($match.dump_str('mob', ' ', '').index($result)),
               $full-description;
        }
    }
}

sub match_perl6regex($pattern, $target) {
    my $rule = %cached{$pattern} //= GGE::Perl6Regex.new($pattern);
    return $rule($target);
}

sub backslash_escape($string) {
    return $string.trans(['\n', '\r', '\e', '\t', '\f'] =>
                         ["\n", "\r", "\e", "\t", "\f"])\
                  .subst(/'\\x' (<[0..9a..f]>**{2..4})/, { chr(:16($0)) }, :g);
}

done_testing;
