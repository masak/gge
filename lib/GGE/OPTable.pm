use v6;

use GGE::Match;
use GGE::Perl6Regex;

class GGE::OPTable {
    # RAKUDO: Must define these within the class for them to be visible.
    constant GGE_OPTABLE_EXPECT_TERM   = 0x01;
    constant GGE_OPTABLE_EXPECT_OPER   = 0x02;

    constant GGE_OPTABLE_TERM          = 0x10;
    constant GGE_OPTABLE_POSTFIX       = 0x20;
    constant GGE_OPTABLE_CLOSE         = 0x30;
    constant GGE_OPTABLE_PREFIX        = 0x40;
    constant GGE_OPTABLE_INFIX         = 0x60;
    constant GGE_OPTABLE_POSTCIRCUMFIX = 0x80;
    constant GGE_OPTABLE_CIRCUMFIX     = 0x90;

    has %!tokens;
    has %!keys;
    has %!klen;

    has %!sctable =
            'term:'          => { syncat => GGE_OPTABLE_TERM,
                                  expect => 0x0201 },
            'postfix:'       => { syncat => GGE_OPTABLE_POSTFIX,
                                  expect => 0x0202, arity => 1 },
            'close:'         => { syncat => GGE_OPTABLE_CLOSE,
                                  expect => 0x0202 },
            'prefix:'        => { syncat => GGE_OPTABLE_PREFIX,
                                  expect => 0x0101, arity => 1 },
            'infix:'         => { syncat => GGE_OPTABLE_INFIX,
                                  expect => 0x0102, arity => 2 },
            'postcircumfix:' => { syncat => GGE_OPTABLE_POSTCIRCUMFIX,
                                  expect => 0x0102, arity => 2 },
            'circumfix:'     => { syncat => GGE_OPTABLE_CIRCUMFIX,
                                  expect => 0x0101, arity => 1 },
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
        my $key = $name.substr($name.index(':') + 1);
        %opts<assoc> //= 'left';
        %opts<name> = $name;
        %!tokens{$name} = %opts;
        if defined (my $ix = $key.index(' ')) {
            my $keyclose = $key.substr($ix + 1);
            %opts<keyclose> = $keyclose;
            $key .= substr(0, $ix);
            self.newtok("close:$keyclose", :equiv($name),
                        :expect(%opts<expectclose> // 0x0202),
                        :nows(%opts<nows>));
        }

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
        my $stoptoken = %opts<stop> // '';
        if $stoptoken.substr(0, 1) eq ' ' {
            $stoptoken .= substr(1);
        }
        my $circumnest = 0;
        my $expect = GGE_OPTABLE_EXPECT_TERM;
        my &shift_oper = -> $name, $key {
            my $op = GGE::Match.new(:from($pos),
                                    :to($pos + $key.chars),
                                    :target($text));
            $op<type> = $name;
            push @tokenstack, %!tokens{$name};
            push @operstack, $op;
            $pos = $op.to;
            $expect = %!tokens{$name}<expect> +> 8;
        };
        my &reduce = {
            my $top = pop @tokenstack;
            my $oper = pop @operstack;
            my $reduce = True;
            if $top<syncat> == GGE_OPTABLE_CLOSE {
                $top = pop @tokenstack;
                $oper = pop @operstack;
            }
            elsif $top<syncat> >= GGE_OPTABLE_POSTCIRCUMFIX {
                pop @termstack;
                $reduce = False;
                if $top<syncat> == GGE_OPTABLE_CIRCUMFIX {
                    push @termstack, GGE::Match.new(:from($pos),
                                                    :to($pos-1),
                                                    :target($text));
                }
            }
            if $reduce {
                my @temp;
                my $arity = $top<arity>;
                for ^$arity {
                    @temp.push(pop(@termstack));
                }
                # The POSTCIRCUMFIX condition here is worrying because there's
                # nothing corresponding in PGE, as far as I can see. But the
                # tests mandate it.
                if $top<syncat> == GGE_OPTABLE_POSTCIRCUMFIX || ?@temp[0] {
                    for reverse ^$arity {
                        $oper.push( @temp[$_] );
                    }
                    if $top<assoc> eq 'list' && $oper<type> eq @temp[1]<type> {

                        @temp[1].push($oper.llist[1]);
                        $oper = @temp[1];
                    }
                    push @termstack, $oper;
                }
                else {
                    # Not sure about this one...
                    for 1..^$arity {
                        push @termstack, @temp[$_];
                    }
                    $pos = -1;
                }
            }
        };
        while $pos < $text.chars {
            my $stop_matching = False;
            if $stoptoken
               && $text.substr($pos, $stoptoken.chars) eq $stoptoken
               && $circumnest == 0 {
                $stop_matching = True;
                last;
            }
            my $wspos = $pos;
            $pos++ while $text.substr($pos, 1) ~~ /\s/;
            my $nows = $pos != $wspos;
            my $last_pos = $pos;
            my $key_firstchar = $text.substr($pos, 1);
            my $maxlength = %!klen{$key_firstchar} // 0;
            my $key = $text.substr($pos, $maxlength);
            my $found_oper = False;
            loop {
                if $text.substr($pos, $key.chars) ne $key {
                    last if $key eq '';
                    $key .= chop();
                    next;
                }
                for (%!keys{$key} // []).list -> $token {
                    my $name = $token<name>;
                    if $token.exists('parsed') {
                        my $routine = $token<parsed>;
                        if $routine ~~ GGE::Perl6Regex {
                            # We don't do this trick yet :/
                            last;
                        }
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
                    elsif $expect +& $token<expect>
                          && !($token<nows> && $nows) {
                        if @operstack {
                            my $top = @tokenstack[*-1];
                            my $topcat = $top<syncat>;
                            if $token<syncat> == GGE_OPTABLE_CLOSE {
                                unless $circumnest {
                                    $stop_matching = True;
                                    last;
                                }
                                if $topcat < GGE_OPTABLE_POSTCIRCUMFIX {
                                    reduce;
                                }
                                $top = @tokenstack[*-1];
                                if $top<keyclose> ne $key {
                                    $stop_matching = True;
                                    last;
                                }
                                --$circumnest;
                            }
                            elsif $token<syncat> >= GGE_OPTABLE_POSTCIRCUMFIX {
                                ++$circumnest;
                                # go directly to shift
                            }
                            elsif $topcat == $token<syncat>
                                          == GGE_OPTABLE_INFIX {
                                # XXX: You guessed it -- the addition of
                                #      a hundred equals signs is kind of
                                #      a hack.
                                my $topprec = $top<precedence> ~ '=' x 100;
                                my $prec = $token<precedence> ~ '=' x 100;
                                my $topassoc = $top<assoc>;
                                if $topprec gt $prec
                                   || $topprec eq $prec
                                      && $topassoc ne 'right' {
                                    reduce;
                                }
                            }
                            elsif all($topcat, $token<syncat>)
                                  == GGE_OPTABLE_PREFIX
                                   | GGE_OPTABLE_INFIX
                                   | GGE_OPTABLE_POSTFIX {
                                # XXX: You guessed it -- the addition of
                                #      a hundred equals signs is kind of
                                #      a hack.
                                my $topprec = $top<precedence> ~ '=' x 100;
                                my $prec = $token<precedence> ~ '=' x 100;
                                if $topprec gt $prec {
                                    reduce;
                                }
                            }
                        }
                        elsif $token<syncat> >= GGE_OPTABLE_POSTCIRCUMFIX {
                            ++$circumnest;
                            # go directly to shift
                        }
                        shift_oper($name, $key);
                        $found_oper = True;
                        last;
                    }
                }
                last if $found_oper || $stop_matching;
                if $key eq '' {
                    if $expect +& GGE_OPTABLE_EXPECT_TERM {
                        if @tokenstack && @tokenstack[*-1]<nullterm> {
                            $expect = GGE_OPTABLE_EXPECT_OPER;
                            # insert a dummy term to make reduce work
                            push @termstack, GGE::Match.new(:from($pos),
                                                            :to($pos-1),
                                                            :target($text));
                            # There might be better ways to restart the loop,
                            # but let's do it this way for now.
                            $key = $text.substr($pos, $maxlength);
                            next;
                        }
                        else {
                            $pos = -1;
                            $stop_matching = True;
                            last;
                        }
                    }
                    else {
                        last;
                    }
                }
                $key .= chop();
            }
            if $stop_matching || $last_pos == $pos {
                last;
            }
            $m.to = $pos;
        }
        if !@termstack {
            $m.to = -1;
        }
        else {
            if $expect +& GGE_OPTABLE_EXPECT_TERM {
                # insert a dummy term to make reduce work
                push @termstack, GGE::Match.new(:from($pos),
                                                :to($pos-1),
                                                :target($text));
            }
            while @tokenstack >= 1 {
                reduce;
            }
        }
        if @termstack && ?@termstack[0] {
            $m<expr> = @termstack[0];
            if $pos <= 0 {
                $m.to = @termstack[0].to;
            }
        }
        else {
            $m.to = -1;
        }
        $m
    }
}
