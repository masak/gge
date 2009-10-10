use v6;

use GGE::Match;

class GGE::OPTable {
    # RAKUDO: Must define these within the class for them to be visible.
    constant GGE_OPTABLE_EXPECT_TERM = 0x01;
    constant GGE_OPTABLE_EXPECT_OPER = 0x02;

    has %!tokens;
    has %!keys;
    has %!klen;

    has %!sctable =
            'term:'          => { expect => 0x0201             },
            'postfix:'       => { expect => 0x0202, arity => 1 },
            'prefix:'        => { expect => 0x0101, arity => 1 },
            'infix:'         => { expect => 0x0102, arity => 2 },
    ;

    method newtok($name, *%opts) {
        my $category = $name.substr(0, $name.index(':') + 1);
        if %!sctable{$category} -> %defaults {
            %opts{$_} //= %defaults{$_} for %defaults.keys;
        }

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
        %opts<name> = $name;
        %!tokens{$name} = %opts;

        my $key = $name.substr($name.index(':') + 1);
        my $keylen = $key.chars;
        my $key_firstchar = $key.substr(0, 1);
        # RAKUDO: max=
        if $key_firstchar && !%!klen.exists($key_firstchar)
           || %!klen{$key_firstchar} < $keylen {
            %!klen{$key_firstchar} = $keylen;
        }

        # RAKUDO: Comma after %opts shouldn't be necessary
        (%!keys{$key} //= []).push({%opts,});
    }

    method parse($text, *%opts) {
        my $m = GGE::Match.new(:target($text));
        my $pos = 0;
        my (@termstack, @tokenstack, @operstack);
        my $expect = GGE_OPTABLE_EXPECT_TERM;
        my &shift_oper = -> $key {
            my $name = $key.substr($key.index(':') + 1);
            my $op = GGE::Match.new(:from($pos),
                                    :to($pos + $name.chars),
                                    :target($text));
            $op<type> = $key;
            push @tokenstack, $op;
            push @operstack, $op;
            $pos = $op.to;
            $expect = %!tokens{$key}<expect> +> 8;
        };
        my &reduce = {
            pop @tokenstack;
            my $oper = pop @operstack;
            my @temp;
            my $arity = %!tokens{$oper<type>}<arity>;
            for ^$arity {
                @temp.push(pop(@termstack));
            }
            if ?@temp[0] {
                for reverse ^$arity {
                    $oper.push( @temp[$_] );
                }
                if %!tokens{$oper<type>}<assoc> eq 'list'
                   && $oper<type> eq @temp[1]<type> {

                    @temp[1].push($oper.llist[1]);
                    $oper = @temp[1];
                }
                push @termstack, $oper;
            }
            else {
                push @termstack, @temp[1];
                $pos = -1;
            }
        };
        while $pos < $text.chars {
            $pos++ while $text.substr($pos, 1) ~~ /\s/;
            my $last_pos = $pos;
            my $stop_matching = False;
            my $key_firstchar = $text.substr($pos, 1);
            my $maxlength = %!klen{$key_firstchar} // 0;
            my $key = $text.substr($pos, $maxlength);
            my $found_oper = False;
            loop {
                for (%!keys{$key} // []).list -> $token {
                    my $name = $token<name>;
                    if $token.exists('parsed') {
                        my $routine = $token<parsed>;
                        my $oper = $routine($m);
                        if $oper.to > $pos {
                            unless $expect +& $token<expect> {
                                $stop_matching = True;
                                last;
                            }
                            $pos = $oper.to;
                            $oper<type> = $name;
                            push @termstack, $oper;
                            $expect = $token<expect> +> 8;
                            $found_oper = True;
                            last;
                        }
                    }
                    if $expect +& $token<expect> {
                        if @operstack {
                            my $top = @operstack[*-1];
                            my $toptype = $top<type>;
                            # XXX: You guessed it -- the addition of a hundred
                            #      equals signs is kind of a hack.
                            my $topprec = %!tokens{$toptype}<precedence>
                                          ~ '=' x 100;
                            my $prec = %!tokens{$name}<precedence> ~ '=' x 100;
                            my $topassoc = %!tokens{$toptype}<assoc>;
                            if $topprec gt $prec
                               || $topprec eq $prec && $topassoc ne 'right' {
                                reduce;
                            }
                        }
                        shift_oper($name);
                        $found_oper = True;
                        last;
                    }
                }
                last if $found_oper;
                last if $key eq '';
                $key .= chop();
            }
            if $stop_matching || $last_pos == $pos {
                last;
            }
            $m.to = $pos;
        }
        if $expect +& GGE_OPTABLE_EXPECT_TERM {
            # insert a dummy term to make reduce work
            push @termstack, GGE::Match.new(:from($pos),
                                            :to($pos-1),
                                            :target($text));
        }
        while @tokenstack >= 1 {
            reduce;
        }
        $m<expr> = @termstack[0];
        if $pos <= 0 {
            $m.to = @termstack[0].to;
        }
        $m
    }
}
