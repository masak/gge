use v6;

use GGE::Exp;
use GGE::Traversal;

class GGE::Cursor {

    has GGE::Traversal $!traversal;
    has Str $!target;
    has Int $.pos;

    submethod BUILD(GGE::Exp :$exp, Str :$!target, Int :$!pos) {
        $!traversal = GGE::Traversal.new(:$exp);
    }

    method matches(:$debug) {
        my &DEBUG = $debug ?? -> *@_ { say @_ } !! -> *@ {};
        DEBUG "Starting match at pos $!pos";

        my @savepoints;
        my $backtracking = False;
        my $current = $!traversal.next.<START>;
        while $current ne 'END' {
            if $backtracking {
                if $current.backtrack().() {
                    $backtracking = False;
                }
                else {
                    pop @savepoints;
                    return False unless @savepoints; # XXX acabcabbcac
                    $current = @savepoints[*-1];
                    redo;
                }
            }
            else {
                my $old-pos = $!pos;
                if $current.matches($!target, $!pos) {
                    DEBUG "MATCH: '{$current.ast}' at pos $old-pos";
                }
                else {
                    DEBUG "MISMATCH: '{$current.ast}' at pos $old-pos";
                    return False unless @savepoints; # XXX acabcabbcac
                    DEBUG 'Backtracking...';
                    $current = @savepoints[*-1];
                    $backtracking = True;
                    redo;
                }
                if $current ~~ GGE::Exp::Quant | GGE::Exp::Alt {
                    push @savepoints, $current;
                }
            }
            $current = $!traversal.next.{$current.WHICH};
        }
        return True;
    }
}

class GGE::Exp::Quant is also {
    has &.backtrack = { False };

    method matches($string, $pos is rw) {
        for ^self.hash-access('min') {
            return False if !self[0].matches($string, $pos);
        }
        my $n = self.hash-access('min');
        if self.hash-access('backtrack') == EAGER {
            &!backtrack = {
                $n++ < self.hash-access('min') && self[0].matches($string, $pos)
            };
        }
        else {
            my @positions;
            while $n++ < self.hash-access('min') {
                push @positions, $pos;
                last if !self[0].matches($string, $pos);
            }
            if self.hash-access('min') == GREEDY {
                &!backtrack = {
                    @positions && $pos = pop @positions
                };
            }
        }
        return True;
    }
}

class GGE::Exp::Alt is also {
    has &.backtrack = { False };

    method matches($string, $pos is rw) {
        &!backtrack = {
            &!backtrack = { False };
            my GGE::Cursor $cursor .= new(:exp(self.llist[1]),
                                          :target($string), :$pos);
            if $cursor.matches() {
                $pos = $cursor.pos;
                return True;
            }
            return False;
        };
        my GGE::Cursor $cursor .= new(:exp(self.llist[0]),
                                      :target($string), :$pos);
        if $cursor.matches() {
            $pos = $cursor.pos;
            return True;
        }
        &!backtrack();
    }
}
