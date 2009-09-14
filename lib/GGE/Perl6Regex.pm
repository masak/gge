use v6;
use GGE::Match;

class GGE::Perl6Regex {
    has $!pattern;

    method new($pattern) {
        return self.bless(*, :$pattern);
    }

    submethod p($pos, $substr) {
        $!pattern.substr($pos, $substr.chars) eq $substr;
    }

    method postcircumfix:<( )>($target) {
        my $rxpos = 0;
        my @terms;
        while $rxpos < $!pattern.chars {
            my $term;
            if (my $op = $!pattern.substr($rxpos + 1, 1)) eq '*'|'+'|'?' {
                $term = { :type<greedy>, :min(0), :max(Inf),
                          :expr($!pattern.substr($rxpos, 1)) };
                if $op eq '+' {
                    $term<min> = 1;
                }
                elsif $op eq '?' {
                    $term<max> = 1;
                }
                $rxpos += 2;
                if self.p($rxpos, ':') {
                    $term<ratchet> = True;
                    ++$rxpos;
                }
                if self.p($rxpos, '!') {
                    ++$rxpos;
                }
                elsif self.p($rxpos, '?') {
                    $term<type> = 'eager';
                    ++$rxpos;
                }
            }
            else {
                $term = { :type<greedy>, :min(1), :max(1),
                          :expr($!pattern.substr($rxpos, 1)) };
                $rxpos++;
            }
            push @terms, $term;
        }
        my $termindex = 0;
        my ($from, $to) = 0, 0;
        my $backtracking = False;
        while 0 <= $termindex < +@terms {
            given @terms[$termindex] {
                .<reps> //= 0;
                my $l = .<expr>.chars;
                # RAKUDO: Must do this because there are no labels
                my $failed = False;
                while .<reps> < .<min> && !$failed {
                    if .<expr> eq $target.substr($to, $l) {
                        $to += $l;
                        .<reps>++;
                    }
                    else {
                        .<reps> = 0;
                        $failed = True;
                    }
                }
                if $failed {
                    $backtracking = True;
                    $termindex--;
                    next;
                }
                if $backtracking {
                    if .<type> eq 'greedy' {
                        # we were too greedy, so try to back down one
                        if .<reps> > .<min> {
                            $to -= $l;
                            .<reps>--;
                        }
                        else {
                            $termindex--;
                            next;
                        }
                    }
                    else { # we were too eager, so try to add one
                        if .<reps> < .<max>
                           && .<expr> eq $target.substr($to, $l) {
                            $to += $l;
                            .<reps>++;
                        }
                        else {
                            $termindex--;
                            next;
                        }
                    }
                    $backtracking = False;
                }
                elsif .<type> eq 'greedy' {
                    while .<reps> < .<max>
                          && .<expr> eq $target.substr($to, $l) {
                        $to += $l;
                        .<reps>++;
                    }
                }
                $termindex++;
            }
        }
        if $termindex < 0 {
            $to = -2;
        }
        return GGE::Match.new(:$target, :$from, :$to);
    }
}
