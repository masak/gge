use v6;
use GGE::Exp;

class GGE::Exp::RxContainer is GGE::Exp {
}

class GGE::TreeSpider {
    has GGE::Exp $!top;
    has Str      $!target;
    has Int      $!from;
    has Int      $!pos;
    has Bool     $!iterate-positions;

    has GGE::Exp $!current;
    has Int      $!pos;
    has Action   $!last;
    has GGE::Exp @!nodestack;
    has          @!padstack;
    has          %!savepoints;

    submethod BUILD(GGE::Exp :$regex!, Str :$!target!, :$pos!) {
        $!top = GGE::Exp::RxContainer.new();
        $!top[0] = $regex;
        # RAKUDO: Smartmatch on type yields an Int, must convert to Bool
        #         manually. [perl #71462]
        if $!iterate-positions = ?($pos ~~ Whatever) {
            $!from = 0;
        }
        else {
            $!from = $pos;
        }
        $!current = $!top;
        $!last = DESCEND;
    }

    method crawl(:$debug) {
        my &debug = $debug ?? -> *@_ { $*ERR.say(|@_) } !! -> *@_ { ; };
        $!pos = $!from;
        loop {
            my %pad = $!last == DESCEND ?? (:pos($!pos)) !! pop @!padstack;
            my $nodename = $!current.WHAT.perl.subst(/.* '::'/, '');
            my $fragment = ($!target ~ '«END»').substr($!pos, 5);
            my $action = do given $!last {
                when DESCEND   { $!current.start($!target, $!pos, %pad) }
                when MATCH     { $!current.succeeded(%pad)              }
                when FAIL      { $!current.failed($!pos, %pad)          }
                when BACKTRACK { $!current.backtracked($!pos, %pad)     }
            };
            # if $action == DESCEND && %!savepoints.exists($!current) { ... }
            if $action != DESCEND {
                debug sprintf '%12s matching "%-5s": %s',
                              $nodename, $fragment, $action.name;
            }
            %pad<pos> = $!pos;
            push @!padstack, \%pad;
            if $!last == DESCEND {
                push @!nodestack, $!current;
            }
            # if $!last == FAIL { ... }
            # Register savepoint
            if $action == DESCEND {
                $!current = $!current[ $!current ~~ GGE::Exp::Concat
                                       ?? %pad<child> !! 0 ];
            }
            else {
                pop @!nodestack;
                last unless @!nodestack;
                $!current = @!nodestack[*-1];
                pop @!padstack;
            }
            $!last = $action;
        }

        if $!last == MATCH {
            GGE::Match.new(:target($!target), :from($!from), :to($!pos));
        }
        else {
            GGE::Match.new(:target($!target), :from(0), :to(-2));
        }
    }
}
