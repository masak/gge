use v6;
use GGE::Match;

class GGE::Perl6Regex {
    has $!pattern;

    method new($pattern) {
        return self.bless(*, :$pattern);
    }

    method postcircumfix:<( )>($target) {
        my ($from, $to, $rxpos) = 0, 0, 0;
        while $rxpos < $!pattern.chars {
            if $!pattern.substr($rxpos + 1, 1) eq '*' {
                while $!pattern.substr($rxpos, 1) eq $target.substr($to, 1) {
                    $to++;
                }
                $rxpos += 2;
                if $!pattern.substr($rxpos, 1) eq ':' {
                    ++$rxpos;
                }
                if $!pattern.substr($rxpos, 1) eq '!' {
                    ++$rxpos;
                }
            }
            elsif $!pattern.substr($rxpos + 1, 1) eq '+' {
                if $!pattern.substr($rxpos, 1) ne $target.substr($to, 1) {
                    last;
                }
                $to++;
                while $!pattern.substr($rxpos, 1) eq $target.substr($to, 1) {
                    $to++;
                }
                $rxpos += 2;
                if $!pattern.substr($rxpos, 1) eq ':' {
                    ++$rxpos;
                }
                if $!pattern.substr($rxpos, 1) eq '!' {
                    ++$rxpos;
                }
            }
            elsif $!pattern.substr($rxpos + 1, 1) eq '?' {
                if $!pattern.substr($rxpos, 1) eq $target.substr($to, 1) {
                    $to++;
                }
                $rxpos += 2;
                if $!pattern.substr($rxpos, 1) eq ':' {
                    ++$rxpos;
                }
                if $!pattern.substr($rxpos, 1) eq '!' {
                    ++$rxpos;
                }
            }
            elsif $!pattern.substr($rxpos, 1) eq $target.substr($to, 1) {
                $to++;
                $rxpos++;
            }
            else {
                last;
            }
        }
        if $rxpos < $!pattern.chars {
            $to = -2;
        }
        return GGE::Match.new(:$target, :$from, :$to);
    }
}
