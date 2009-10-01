use v6;
use GGE::Match;
use GGE::Exp;

class GGE::Perl6Regex {
    has $!pattern;

    method new($pattern) {
        return self.bless(*, :$pattern);
    }

    submethod p($pos, $substr) {
        $!pattern.substr($pos, $substr.chars) eq $substr;
    }

    sub matches($string, $pos is rw, $pattern) {
        if $pattern ~~ GGE::Exp::CCShortcut {
            if $pattern.type eq 's' && $string.substr($pos, 1) eq ' ' {
                ++$pos;
                return True;
            }
            elsif $pattern.type eq 'S' && $pos < $string.chars
                  && $string.substr($pos, 1) ne ' ' {
                ++$pos;
                return True;
            }
        }
        elsif $pattern ~~ GGE::Exp::Anchor {
            return $pos == 0;
        }
        else {
            if $pos >= $string.chars {
                return False;
            }
            if $pattern eq '.' {
                ++$pos;
                return True;
            }
            else {
                if $string.substr($pos, $pattern.chars) eq $pattern {
                    $pos += $pattern.chars;
                    return True;
                }
            }
        }
        return False;
    }

    submethod parse-backtracking-modifiers($rxpos is rw, $quant) {
        if self.p($rxpos, ':?') {
            $quant.ratchet = False;
            $quant.type = 'eager';
            $rxpos += 2;
        }
        elsif self.p($rxpos, ':!') {
            $quant.ratchet = False;
            $rxpos += 2;
        }
        elsif self.p($rxpos, '?') {
            $quant.ratchet = False;
            $quant.type = 'eager';
            ++$rxpos;
        }
        elsif self.p($rxpos, '!') {
            $quant.ratchet = False;
            ++$rxpos;
        }
        elsif self.p($rxpos, ':') {
            $quant.ratchet = True;
            ++$rxpos;
        }
    }

    method postcircumfix:<( )>($target, :$debug) {
        my $rxpos = 0;
        my $ratchet = False;
        my @terms;
        while $rxpos < $!pattern.chars {
            my $term;
            if self.p($rxpos, ':ratchet') {
                $ratchet = True;
                $rxpos += 8;
                next;
            }
            elsif self.p($rxpos, '**') {
                $term = GGE::Exp::Quant.new( :type<greedy>, :$ratchet,
                                             :expr(@terms.pop) );
                $rxpos += 2;
                self.parse-backtracking-modifiers($rxpos, $term);
                my $brackets = False;
                if self.p($rxpos, '{') {
                    $brackets = True;
                    ++$rxpos;
                }
                # XXX: Need to generalize this into parsing several digits
                $term.min = $term.max = $!pattern.substr($rxpos, 1);
                $rxpos++;
                if self.p($rxpos, '..') {
                    $rxpos += 2;
                    $term.max = $!pattern.substr($rxpos, 1);
                    ++$rxpos;
                }
                if $brackets {
                    die 'No "}" found'
                        unless self.p($rxpos, '}');
                    $rxpos += 1;
                }
            }
            elsif (my $op = $!pattern.substr($rxpos, 1)) eq '*'|'+'|'?' {
                $term = GGE::Exp::Quant.new( :type<greedy>, :min(0), :max(Inf),
                                             :$ratchet, :expr(@terms.pop) );
                if $op eq '+' {
                    $term.min = 1;
                }
                elsif $op eq '?' {
                    $term.max = 1;
                }
                ++$rxpos;
                self.parse-backtracking-modifiers($rxpos, $term);
            }
            elsif self.p($rxpos, ' ') {
                ++$rxpos;
                next;
            }
            elsif self.p($rxpos, '\\s'|'\\S') {
                my $type = $!pattern.substr($rxpos + 1, 1);
                $term = GGE::Exp::CCShortcut.new(:$type);
                $rxpos += 2;
            }
            elsif self.p($rxpos, '^') {
                my $type = $!pattern.substr($rxpos + 1, 1);
                $term = GGE::Exp::Anchor.new(:$type);
                ++$rxpos;
            }
            else {
                $term = $!pattern.substr($rxpos, 1);
                ++$rxpos;
            }
            push @terms, $term;
        }
        for ^$target.chars -> $from {
            my $to = $from;
            my $termindex = 0;
            my $backtracking = False;
            my &DEBUG = $debug
                            ?? -> *@m { $*ERR.say: |@m,
                                                   " at index $termindex,",
                                                   " position $to" }
                            !! -> *@m { #`[debugging off] };
            my @marks;
            while 0 <= $termindex < +@terms {
                given @terms[$termindex] {
                    when Str|GGE::Exp::Anchor {
                        if $backtracking {
                            $to = @marks.pop();
                            $termindex--;
                            next;
                        }
                        my $old-to = $to;
                        if matches($target, $to, $_) {
                            DEBUG "Matched '$_'";
                            DEBUG 'Proceeding';
                            $termindex++;
                            @marks.push($old-to + 0);
                        }
                        else {
                            DEBUG 'Failed to match ', $_;
                            DEBUG 'Turning on backtracking';
                            $backtracking = True;
                            $termindex--;
                            next;
                        }
                    }
                    unless $backtracking {
                        .reps = 0;
                    }
                    # RAKUDO: Must do this because there are no labels
                    my $failed = False;
                    while .reps < .min && !$failed {
                        my $old-to = $to;
                        if matches($target, $to, .expr) {
                            DEBUG q[Matched '], .expr, q['];
                            .reps++;
                        # RAKUDO: Have to change the value non-destructively
                        #         so that it, and not a reference to it gets
                        #         stored in the array
                            .marks.push($old-to + 0);
                        }
                        else {
                            DEBUG 'Failed to match ', .expr;
                            .reps = 0;
                            $failed = True;
                        }
                    }
                    if $failed {
                        DEBUG 'Turning on backtracking';
                        $backtracking = True;
                        $termindex--;
                        next;
                    }
                    if $backtracking {
                        if .ratchet {
                            DEBUG 'Failed to match';
                            $termindex = -1;
                            last;
                        }
                        elsif .type eq 'greedy' {
                            # we were too greedy, so try to back down one
                            if .reps > .min {
                                $to = .marks.pop();
                                DEBUG "Backing left";
                                .reps--;
                            }
                            else {
                                DEBUG 'Retreating';
                                $termindex--;
                                next;
                            }
                        }
                        else { # we were too eager, so try to add one
                            if .reps < .max
                               && matches($target, $to, .expr) {
                                DEBUG "Backing right";
                                .reps++;
                            }
                            else {
                                DEBUG 'Retreating';
                                $termindex--;
                                next;
                            }
                        }
                        DEBUG 'Turning off backtracking';
                        $backtracking = False;
                    }
                    elsif .type eq 'greedy' {
                        my $old-to = $to;
                        while .reps < .max
                              && matches($target, $to, .expr) {
                            DEBUG q[Matched '], .expr, q['];
                            .reps++;
                        # RAKUDO: Have to change the value non-destructively
                        #         so that it, and not a reference to it gets
                        #         stored in the array
                            .marks.push($old-to + 0);
                            $old-to = $to;
                        }
                    }
                    DEBUG 'Proceeding';
                    $termindex++;
                }
            }
            if $termindex == +@terms {
                DEBUG 'Match complete';
                return GGE::Match.new(:$target, :$from, :$to);
            }
        }
        return GGE::Match.new(:$target, :from(0), :to(-2));
    }
}
