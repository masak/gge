use v6;
use GGE::Exp;

class GGE::Exp::Regex   is GGE::Exp
                      does GGE::Backtracking
                      does GGE::Container {
    method start($, $, %) { DESCEND }
}

class GGE::TreeSpider {
    has GGE::Exp   $!top;
    has Str        $!target;
    has Int        $!from;
    has Int        $!pos;
    has Bool       $!iterate-positions;
    has GGE::Match $!match;
    has            @!caps;

    has GGE::Exp   $!current;
    has Int        $!pos;
    has Action     $!last;
    has GGE::Exp   @!nodestack;
    has            @!padstack;
    has            %!savepoints;

    submethod BUILD(GGE::Exp :$regex!, Str :$!target!, :$pos!) {
        $!top = GGE::Exp::Regex.new();
        $!top[0] = $regex;
        # RAKUDO: Smartmatch on type yields an Int, must convert to Bool
        #         manually. [perl #71462]
        if $!iterate-positions = ?($pos ~~ Whatever) {
            $!from = 0;
        }
        else {
            $!from = $pos;
        }
    }

    method crawl(:$debug) {
        my &debug = $debug ?? -> *@_ { $*ERR.say(|@_) } !! -> *@_ { ; };
        $!match = GGE::Match.new(:target($!target));
        my @start-positions = $!iterate-positions ?? ^$!target.chars !! $!from;
        for @start-positions -> $start-position {
            debug 'Starting at position ', $start-position;
            $!match.from = $!pos = $start-position;
            $!match.clear;
            @!caps = ();
            $!current = $!top;
            $!last = DESCEND;
            loop {
                my %pad = $!last == DESCEND ?? (:pos($!pos)) !! pop @!padstack;
                my $nodename = $!current.WHAT.perl.subst(/.* '::'/, '');
                if $!current.?contents {
                    $nodename ~= '(' ~ $!current.contents ~ ')';
                }
                my $fragment = ($!target ~ '«END»').substr($!pos, 5)\
                               .trans( [ "\n", "\t" ] => [ "\\n", "\\t" ] )\
                               .substr(0, 5);
                if $!last == FAIL {
                    if %!savepoints.exists($!current.WHICH)
                       && +%!savepoints{$!current.WHICH} {
                        my @sp = %!savepoints{$!current.WHICH}.pop.list;
                        @!nodestack = @sp[0].list;
                        @!padstack  = @sp[1].list;
                        $!current = @!nodestack[*-1];
                        $!last = BACKTRACK;
                        next;
                    }
                }
                if $!last == BACKTRACK {
                    $!pos = %pad<pos>;
                }
                if $!current ~~ GGE::Exp::Quant
                   && $!current[0] ~~ GGE::Exp::CGroup
                   && $!last == DESCEND {
                    @!caps.push([]);
                }
                my $action = do given $!last {
                    when DESCEND    { $!current.start($!target, $!pos, %pad) }
                    when MATCH      { $!current.succeeded($!pos, %pad)       }
                    when FAIL       { $!current.failed($!pos, %pad)          }
                    when BACKTRACK  { $!current.backtracked($!pos, %pad)     }
                    when FAIL_GROUP { $!current.failed-group($!pos, %pad)    }
                    when FAIL_RULE  { $!current.failed-rule($!pos, %pad)     }
                    when *          { die 'Unknown action ', $!last.name     }
                };
                if $action == DESCEND && %!savepoints.exists($!current.WHICH) {
                    %!savepoints.delete($!current.WHICH);
                }
                if $action != DESCEND
                   && ($!last == BACKTRACK || !($!current ~~ GGE::Container)) {
                    my $participle
                        = $!last == BACKTRACK ?? 'backtracking' !! 'matching';
                    debug sprintf '%-20s %12s "%-5s": %s',
                                   $nodename,
                                         $participle,
                                              $fragment,
                                                      $action.name;
                }
                %pad<pos> = $!pos;
                push @!padstack, \%pad;
                if $!last == DESCEND {
                    push @!nodestack, $!current;
                }
                if $!current ~~ GGE::Backtracking && $action == MATCH {
                    my $index = @!nodestack.end - 1;
                    $index--
                        until @!nodestack[$index] ~~ GGE::Backtracking;
                    my $ancestor = @!nodestack[$index];
                    (%!savepoints{$ancestor.WHICH} //= []).push(
                        [[@!nodestack.list], [@!padstack.list]]
                    );
                }
                if $!current ~~ GGE::Exp::CGroup {
                    given $action {
                        when DESCEND {
                            my $cap = GGE::Match.new(:target($!target),
                                                     :from($!pos));
                            @!caps.push($cap);
                        }
                        when MATCH {
                            @!caps[*-1].to = $!pos;
                            my $cap = pop @!caps;
                            (@!caps ?? @!caps[*-1] !! $!match).push($cap);
                        }
                        when FAIL | FAIL_GROUP | FAIL_RULE {
                            pop @!caps;
                        }
                    }
                }
                elsif $!current ~~ GGE::Exp::Quant
                       && $!current[0] ~~ GGE::Exp::CGroup {
                    given $action {
                        when MATCH {
                            my $cap = pop @!caps;
                            (@!caps ?? @!caps[*-1] !! $!match).push($cap);
                        }
                    }
                }
                if $action == DESCEND {
                    $!current = $!current[ $!current ~~ GGE::MultiChild
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
            if $!last == FAIL_RULE {
                last;
            }
            if $!last == MATCH {
                $!match.to = $!pos;
                return $!match;
            }
        }

        # The match failed
        $!match.from = 0;
        $!match.to   = -2;
        $!match;
    }
}
