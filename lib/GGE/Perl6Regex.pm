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
                $term = GGE::Exp::Literal.new(
                            :value($!pattern.substr($rxpos, 1))
                        );
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
                    when GGE::Exp {
                        if .matches($target, $to) {
                            DEBUG "Matched {$_ ~~ Str ?? "'$_'" !! $_}";
                            $c.proceed;
                        }
                        else {
                            DEBUG 'Failed to match ', $_, ', backtracking';
                            $to = $c.backtrack();
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
