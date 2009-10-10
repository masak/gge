use v6;

use GGE::Match;

class GGE::OPTable {
    # RAKUDO: Must define these within the class for them to be visible.
    constant GGE_OPTABLE_EXPECT_TERM = 0x01;
    constant GGE_OPTABLE_EXPECT_OPER = 0x02;

    has %!tokens;

    method newtok($name, *%opts) {
        if %opts<equiv> -> $t {
            %opts<precedence> = %!tokens{$t}<precedence>;
            %opts<assoc> = %!tokens{$t}<assoc>;
        }
        elsif %opts<looser> -> $t {
            %opts<precedence> = %!tokens{$t}<precedence> ~ '<';
        }
        elsif %opts<tighter> -> $t {
            %opts<precedence> = %!tokens{$t}<precedence> ~ '>';
        }
        %opts<assoc> //= 'left';
        %!tokens{$name} = %opts;
    }

    method parse($text, *%opts) {
        my $m = GGE::Match.new(:target($text));
        my $pos = 0;
        my (@termstack, @tokenstack, @operstack);
        my $expect = GGE_OPTABLE_EXPECT_TERM;
        my &shift_oper = -> $key {
            my $name = $key.substr(6);
            my $op = GGE::Match.new(:from($pos),
                                    :to($pos + $name.chars),
                                    :target($text));
            $op<type> = $key;
            push @tokenstack, $op;
            push @operstack, $op;
            $pos = $op.to;
            $expect = GGE_OPTABLE_EXPECT_TERM;
        };
        my &reduce = {
            pop @tokenstack;
            my $oper = pop @operstack;
            my @temp = pop(@termstack), pop(@termstack);
            $oper.push( @temp[1] );
            $oper.push( @temp[0] );
            if %!tokens{$oper<type>}<assoc> eq 'list'
               && $oper<type> eq @temp[1]<type> {

                @temp[1].push($oper.llist[1]);
                $oper = @temp[1];
            }
            push @termstack, $oper;
        };
        while $pos < $text.chars {
            $pos++ while $text.substr($pos, 1) ~~ /\s/;
            my $last_pos = $pos;
            my $stop_matching = False;
            for %!tokens.keys -> $key {
                if %!tokens{$key}.exists('parsed') {
                    my $routine = %!tokens{$key}<parsed>;
                    my $oper = $routine($m);
                    if $oper.to > $pos {
                        unless $expect +& GGE_OPTABLE_EXPECT_TERM {
                            $stop_matching = True;
                            last;
                        }
                        $pos = $oper.to;
                        $oper<type> = $key;
                        push @termstack, $oper;
                        $expect = GGE_OPTABLE_EXPECT_OPER;
                        last;
                    }
                }
                if $key.substr(0, 6) eq 'infix:' {
                    my $name = $key.substr(6);
                    if $text.substr($pos, $name.chars) eq $name {
                        if @operstack {
                            my $top = @operstack[*-1];
                            my $toptype = $top<type>;
                            # XXX: You guessed it -- the addition of a hundred
                            #      equals signs is kind of a hack.
                            my $topprec = %!tokens{$toptype}<precedence>
                                          ~ '=' x 100;
                            my $prec = %!tokens{$key}<precedence> ~ '=' x 100;
                            my $topassoc = %!tokens{$toptype}<assoc>;
                            if $topprec gt $prec
                               || $topprec eq $prec && $topassoc ne 'right' {
                                reduce;
                            }
                        }
                        shift_oper($key);
                        last;
                    }
                }
            }
            if $stop_matching || $last_pos == $pos {
                last;
            }
            $m.to = $pos;
        }
        while @operstack {
            reduce;
        }
        $m<expr> = @termstack[0];
        $m
    }
}
