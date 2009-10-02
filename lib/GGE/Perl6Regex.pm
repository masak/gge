use v6;
use GGE::Match;
use GGE::Exp;
use GGE::Cursor;

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
            return $pattern.type eq '^' && $pos == 0
                || $pattern.type eq '$' && $pos == $string.chars;
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
            elsif self.p($rxpos, '^'|'$') {
                my $type = $!pattern.substr($rxpos, 1);
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
            my $old-to;
            my &DEBUG = $debug
                            ?? -> *@m { $*ERR.say: |@m,
                                                   " at positions $old-to..$to"
                                      }
                            !! -> *@m { #`[debugging off] };
            my GGE::Cursor $c .= new(@terms, $target);
            while $c.is-active {
                $old-to = $to;
                given $c.current-term {
                    when Str|GGE::Exp::Anchor {
                        if matches($target, $to, $_) {
                            DEBUG "Matched {$_ ~~ Str ?? "'$_'" !! $_}";
                            $c.proceed;
                        }
                        else {
                            DEBUG 'Failed to match ', $_, ', backtracking';
                            $to = $c.backtrack();
                        }
                    }
                    when GGE::Exp::Quant {
                        if !$c.is-backtracking {
                            $c.push($to);
                        }
                        if defined ($to = $c.get) {
                            DEBUG "Matched {$_ ~~ Str ?? "'$_'" !! $_}";
                            $c.proceed;
                        }
                        else {
                            DEBUG 'Failed to match ', $_, ', backtracking';
                            $c.backtrack();
                        }
                    }
                    default {
                        die "Unknown expression type {.WHAT}";
                    }
                }
            }
            if $c.succeeded {
                $old-to = $from;
                DEBUG 'Match complete';
                return GGE::Match.new(:$target, :$from, :$to);
            }
        }
        return GGE::Match.new(:$target, :from(0), :to(-2));
    }
}
