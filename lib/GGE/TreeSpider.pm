use v6;
use GGE::Exp;

class GGE::TreeSpider {
    has GGE::Exp   $!top;
    has Str        $!target;
    has Int        $!from;
    has Int        $!pos;
    has Bool       $!iterate-positions;
    has GGE::Match $!match;
    has            @!capstack;

    has GGE::Exp   $!current;
    has Int        $!pos;
    has Action     $!last;
    # RAKUDO: Originally had @!nodestack typed as 'GGE::Exp', but that
    #         triggered a bug.
    has            @!nodestack;
    has            @!padstack;
    has            @!savepoints;

    submethod BUILD(GGE::Exp :$regex!, Str :$!target!, :$pos!) {
        $!top = $regex;
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
            @!savepoints = ();
            $!match.from = $!pos = $start-position;
            $!match.clear;
            @!capstack = $!match;
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
                if $!last == BACKTRACK {
                    $!pos = %pad<pos>;
                }
                if $!current ~~ GGE::Exp::CGroup
                   && $!last == BACKTRACK {
                    my $cname = $!current.hash-access('cname');
                    @!capstack[*-1].[$cname] = undef;
                }
                if $!current ~~ GGE::Exp::Quant
                   && $!current[0] ~~ GGE::Exp::CGroup
                   && $!last == DESCEND {
                    @!capstack.push([]);
                }
                if $!current ~~ GGE::Exp::Quant
                   && $!current.hash-access('backtrack') == NONE
                   && $!last == DESCEND {
                    %pad<ratchet-savepoints> = +@!savepoints;
                }
                elsif $!current ~~ GGE::Exp::Group
                      && $!last == DESCEND {
                    %pad<group-savepoints> = +@!savepoints;
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
                if $!current ~~ GGE::Exp::Alt
                   && $!last == DESCEND {
                    @!savepoints.push(
                        [[@!nodestack.list], [@!padstack.list]]
                    );
                }
                if $!current ~~ GGE::Backtracking && $action == MATCH {
                    if $!current ~~ GGE::Exp::Quant
                       && $!current.hash-access('backtrack') == NONE {
                        @!savepoints.=splice(0, %pad<ratchet-savepoints>);
                    }
                    else {
                        @!savepoints.push(
                            [[@!nodestack.list], [@!padstack.list]]
                        );
                    }
                }
                if $!current ~~ GGE::Exp::CGroup {
                    given $action {
                        when DESCEND {
                            my $cap = GGE::Match.new( :target($!target),
                                                      :from($!pos) );
                            $cap.hash-access('isscope')
                                = $!current.hash-access('isscope');
                            @!capstack.push($cap);
                        }
                        when MATCH {
                            my $cap = @!capstack.pop;
                            $cap.to = $!pos;
                            # Find a capture that is a scope.
                            my $ix = @!capstack.end;
                            --$ix
                                while $ix > 0
                                      && @!capstack[$ix] !~~ Array
                                      && ! @!capstack[$ix]\
                                             .hash-access('isscope');
                            my $topcap = @!capstack[$ix];
                            if $topcap ~~ Array {
                                $topcap.push($cap);
                            }
                            elsif $!current.hash-access('isarray') {
                                my $cname = $!current.hash-access('cname');
                                ($topcap[$cname] //= []).push($cap);
                            }
                            else {
                                my $cname = $!current.hash-access('cname');
                                $topcap[$cname] = $cap;
                            }
                        }
                        when FAIL | FAIL_GROUP | FAIL_RULE {
                            if $!last != BACKTRACK {
                                @!capstack.pop;
                            }
                        }
                    }
                }
                elsif $!current ~~ GGE::Exp::Quant
                      && $!current[0] ~~ GGE::Exp::CGroup
                      && $action == MATCH {
                    my $array = @!capstack.pop;
                    my $cname = $!current[0].hash-access('cname');
                    @!capstack[*-1].[$cname] = $array;
                }
                elsif $!current ~~ GGE::Exp::Group && $!last == FAIL_GROUP {
                    @!savepoints.=splice(0, %pad<group-savepoints>);
                }
                if $action == DESCEND {
                    $!current = $!current[ $!current ~~ GGE::MultiChild
                                           ?? %pad<child> !! 0 ];
                }
                else {
                    pop @!nodestack;
                    if $action == FAIL && ! @!nodestack && @!savepoints {
                        my @sp = @!savepoints.pop.list;
                        @!nodestack = @sp[0].list;
                        @!padstack  = @sp[1].list;
                        $!current = @!nodestack[*-1];
                        $!last = BACKTRACK;
                        next;
                    }
                    if @!nodestack {
                        $!current = @!nodestack[*-1];
                        pop @!padstack;
                    }
                    else {
                        $!last = $action;
                        last;
                    }
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
