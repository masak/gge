use v6;
use Test;
use GGE;

my $previous-pattern = '';
my $previous-rule;

sub dirname($path) { $path.comb(/<-[/]>+ '/'/).join() } #' (vim fix)

my @test-files = <
    metachars
    quantifiers
    backtrack
    charclass
    modifiers
    captures
    subrules
    lookarounds
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
        $line ~~ /^ (\T*) \t+ (\T+) \t+ (\T+) \t+ (.*) $/
            or die "Unrecognized line format: $line";
        my ($pattern, $target, $result, $description) = $0, $1, $2, $3;
        $target  = $target eq q[''] ?? '' !! backslash_escape(~$target);
        $result  = backslash_escape(~$result);
        my $full-description = "[$test-file" ~ ":$i] $description";
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
    my $rule = $pattern eq $previous-pattern
        ?? $previous-rule
        !! GGE::Perl6Regex.new($pattern);
    $previous-pattern = $pattern;
    $previous-rule = $rule;
    return $rule($target);
}

sub replace_x($s is copy) {
    while defined (my $start = $s.index("\\x")) {
        my $end = $start + 2;
        ++$end while $s.substr($end, 1) ~~ /<[0..9a..fA..F]>/;
        my $n = $s.substr($start + 2, $end - $start - 2);
        $s = $s.substr(0, $start) ~ chr(:16($n)) ~ $s.substr($end);
    }
    $s
}

sub backslash_escape($string) {
    # RAKUDO: No .trans again yet
    #return $string.trans(['\n', '\r', '\e', '\t', '\f'] =>
    #                     ["\n", "\r", "\e", "\t", "\f"])\
    # RAKUDO: No "\e". [RT #75244]
    return replace_x $string.subst(/\\n/, "\n", :g).subst(/\\r/, "\r", :g).subst(/\\e/, "\c[27]", :g).subst(/\\t/, "\t", :g).subst(/\\f/, "\f", :g);
}

done_testing;
