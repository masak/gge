use v6;

use GGE::Exp;

class GGE::Cursor;

has GGE::Exp $!top;
has Str $!target;
has Int $.pos = 0;

method matches() {
    my $current = $!top;
    while $current ~~ GGE::Exp::Modifier {
        $current = $current.llist[0];
    }
    if $current ~~ GGE::Exp::Concat {
        my @savepoints;
        my $backtracking = False;
        loop (my $i = 0; $i < $current.llist.elems; ++$i) {
            my $child = $current.llist[$i];
            if $backtracking {
                if $child.backtrack().() {
                    $backtracking = False;
                }
                else {
                    pop @savepoints;
                    return False unless @savepoints; # XXX acabcabbcac
                    $i = @savepoints[*-1];
                    redo;
                }
            }
            else {
                if $child.matches($!target, $!pos) {
                    # yay! we match!
                }
                else {
                    return False unless @savepoints; # XXX acabcabbcac
                    $i = @savepoints[*-1];
                    $backtracking = True;
                    redo;
                }
                if $child ~~ GGE::Exp::Quant {
                    push @savepoints, $i;
                }
            }
        }
        return True;
    }
    else {
        return $current.matches($!target, $!pos);
    }
}
