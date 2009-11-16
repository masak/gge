use v6;

use GGE::Exp;
use GGE::Traversal;

class GGE::Cursor;

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
            if $current ~~ GGE::Exp::Quant {
                push @savepoints, $current;
            }
        }
        $current = $!traversal.next.{$current.WHICH};
    }
    return True;
}
