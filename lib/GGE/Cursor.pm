use v6;

use GGE::Exp;

class GGE::Cursor;

has GGE::Exp $!top;
has Str $!target;
has Int $.pos = 0;

method matches(:$debug) {
    my &DEBUG = $debug ?? -> *@_ { say @_ } !! -> *@ {};
    DEBUG "Starting match at pos $!pos";
    return self.traverse($!top, :$debug);
}

multi method traverse(GGE::Exp $e) {
    return $e.matches($!target, $!pos);
}

multi method traverse(GGE::Exp::Modifier $e, :$debug) {
    return self.traverse($e.llist[0], :$debug);
}

multi method traverse(GGE::Exp::Concat $e, :$debug) {
    my &DEBUG = $debug ?? -> *@_ { say @_ } !! -> *@ {};
    my @savepoints;
    my $backtracking = False;
    loop (my $i = 0; $i < $e.llist.elems; ++$i) {
        my $child = $e.llist[$i];
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
            my $old-pos = $!pos;
            if $child.matches($!target, $!pos) {
                DEBUG "MATCH: '{$child.ast}' at pos $old-pos";
            }
            else {
                DEBUG "MISMATCH: '{$child.ast}' at pos $old-pos";
                return False unless @savepoints; # XXX acabcabbcac
                DEBUG 'Backtracking...';
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

multi method traverse(GGE::Exp::Alt $e, :$debug) {
    my $keep-pos = $!pos;
    if self.traverse($e.llist[0], :$debug) {
        return True;
    }
    else {
        $!pos = $keep-pos;
        return self.traverse($e.llist[1], :$debug);
    }
}
