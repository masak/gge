use v6;

use GGE::Match;

class GGE::OPTable {
    # RAKUDO: Must define these within the class for them to be visible.
    # RAKUDO: Constants-in-classes broke after a merge. Working around.
    ##constant GGE_OPTABLE_EXPECT_TERM   = 0x01;
    ##constant GGE_OPTABLE_EXPECT_OPER   = 0x02;

    ##constant GGE_OPTABLE_TERM          = 0x10;
    ##constant GGE_OPTABLE_POSTFIX       = 0x20;
    ##constant GGE_OPTABLE_CLOSE         = 0x30;
    ##constant GGE_OPTABLE_PREFIX        = 0x40;
    ##constant GGE_OPTABLE_INFIX         = 0x60;
    ##constant GGE_OPTABLE_POSTCIRCUMFIX = 0x80;
    ##constant GGE_OPTABLE_CIRCUMFIX     = 0x90;
    sub GGE_OPTABLE_EXPECT_TERM { 0x01 }
    sub GGE_OPTABLE_EXPECT_OPER { 0x02 }

    sub GGE_OPTABLE_TERM          { 0x10 }
    sub GGE_OPTABLE_POSTFIX       { 0x20 }
    sub GGE_OPTABLE_CLOSE         { 0x30 }
    sub GGE_OPTABLE_PREFIX        { 0x40 }
    sub GGE_OPTABLE_INFIX         { 0x60 }
    sub GGE_OPTABLE_POSTCIRCUMFIX { 0x80 }
    sub GGE_OPTABLE_CIRCUMFIX     { 0x90 }

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
        if $key_firstchar && (!%!klen.exists($key_firstchar)
                              || %!klen{$key_firstchar} < $keylen) {
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
        my &shift_oper = -> $oper, $token {
            push @tokenstack, $token;
            push @operstack, $oper;
            $pos = $oper.to;
            $expect = $token<expect> +> 8;
        };
        my &reduce = {
            my $top = pop @tokenstack;
            my $oper = pop @operstack;
            my $reduce = True;
            if $top<syncat> == GGE_OPTABLE_CLOSE() {
                $top = pop @tokenstack;
                $oper = pop @operstack;
            }
            elsif $top<syncat> >= GGE_OPTABLE_POSTCIRCUMFIX() {
                pop @termstack;
                $reduce = False;
                if $top<syncat> == GGE_OPTABLE_CIRCUMFIX() {
                    my $matchclass = $top<match> ~~ GGE::Match ??
                                     $top<match> !! GGE::Match;
                    push @termstack, $matchclass.new(:from($pos),
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
                if $top<syncat> == GGE_OPTABLE_POSTCIRCUMFIX() || ?@temp[0] {
                    for reverse ^$arity {
                        $oper.push( @temp[$_] );
                    }
                    if $top<assoc> eq 'list'
                       && @temp[1]
                       && $oper.hash-access('type')
                          eq @temp[1].hash-access('type') {
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
            my $key_firstchar = $text.substr($pos, 1);
            my $maxlength = %!klen{$key_firstchar} // 0;
            my $key = $text.substr($pos, $maxlength);
            my $orig-key = $key;
            my $found_oper = False;
            loop {
                if $text.substr($pos, $key.chars) ne $key {
                    last if $key eq '';
                    $key .= chop();
                    next;
                }
                for (%!keys{$key} // []).list -> $token {
                    next unless $expect +& $token<expect>;
                    next if $token<nows> && $nows;
                    my $name = $token<name>;
                    my $matchclass = %!tokens{$name}<match> ~~ GGE::Match ??
                                     %!tokens{$name}<match> !! GGE::Match;
                    my $oper = $matchclass.new(:from($pos),
                                               :to($pos + $key.chars),
                                               :target($text));
                    $oper.hash-access('type') = $name;
                    if $token.exists('parsed') {
                        my $routine = $token<parsed>;
                        if $routine ~~ Sub|Method {
                            $m.hash-access('KEY') = $key;
                            $m.to = $pos + $key.chars;
                            $oper = $routine($m);
                            $m.delete('KEY');
                            $oper.hash-access('type') = $name;
                            $oper.from = $pos;
                            if $oper.to > $pos {
                                $pos = $oper.to;
                                $found_oper = True;
                            }
                            else {
                                next;
                            }
                        }
                        elsif $routine ~~ Code {
                            # Here we assume that what we got was a PGE regex
                            # routine, and we call it with the text we want
                            # to match as an argument.
                            my $pge-match = $routine($text.substr($pos));
                            if $pge-match.to >= 0 {
                                $oper.to = $pos += $pge-match.to;
                                $found_oper = True;
                            }
                            else {
                                next;
                            }
                        }
                        else {
                            next;
                        }
                    }
                    if $token<syncat> == GGE_OPTABLE_TERM() {
                        push @termstack, $oper;
                        $pos += $key.chars;
                        $expect = $token<expect> +> 8;
                        $found_oper = True;
                        last;
                    }
                    my $shift_reduce_done = False;
                    while !$shift_reduce_done {
                        if @operstack {
                            my $top = @tokenstack[*-1];
                            my $topcat = $top<syncat>;
                            if $token<syncat> == GGE_OPTABLE_CLOSE() {
                                unless $circumnest {
                                    $shift_reduce_done = True;
                                    $stop_matching = True;
                                    last;
                                }
                                if $topcat < GGE_OPTABLE_POSTCIRCUMFIX() {
                                    reduce;
                                    next;
                                }
                                $top = @tokenstack[*-1];
                                if $top<keyclose> ne $key {
                                    $shift_reduce_done = True;
                                    $stop_matching = True;
                                    last;
                                }
                                --$circumnest;
                            }
                            elsif $token<syncat> >= GGE_OPTABLE_POSTCIRCUMFIX() {
                                ++$circumnest;
                                # go directly to shift
                            }
                            elsif $topcat == GGE_OPTABLE_POSTFIX()
                                  && $token<syncat> == GGE_OPTABLE_INFIX()
                                                     | GGE_OPTABLE_POSTFIX() {
                                reduce;
                                next;
                            }
                            elsif $topcat == $token<syncat>
                                          == GGE_OPTABLE_INFIX() {
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
                                    next;
                                }
                            }
                            elsif $topcat == GGE_OPTABLE_PREFIX()
                                           | GGE_OPTABLE_INFIX()
                                  && $token<syncat> == GGE_OPTABLE_INFIX()
                                                     | GGE_OPTABLE_POSTFIX() {
                                # XXX: You guessed it -- the addition of
                                #      a hundred equals signs is kind of
                                #      a hack.
                                my $topprec = $top<precedence> ~ '=' x 100;
                                my $prec = $token<precedence> ~ '=' x 100;
                                if $topprec ge $prec {
                                    reduce;
                                    next;
                                }
                            }
                        }
                        elsif $token<syncat> >= GGE_OPTABLE_POSTCIRCUMFIX() {
                            ++$circumnest;
                            # go directly to shift
                        }
                        shift_oper($oper, $token);
                        $shift_reduce_done = True;
                        $found_oper = True;
                    }
                    last if $found_oper || $stop_matching;
                }
                last if $found_oper || $stop_matching;
                if $key eq '' {
                    if $pos != $wspos {
                        $pos = $wspos;
                        $nows = False;
                        $key = $orig-key;
                        next;
                    }
                    if $expect +& GGE_OPTABLE_EXPECT_TERM() {
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
            if $stop_matching || !$found_oper {
                last;
            }
            $m.to = $pos;
        }
        if !@termstack {
            $m.to = -1;
        }
        else {
            if $expect +& GGE_OPTABLE_EXPECT_TERM() {
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
            $m.hash-access('expr') = @termstack[0];
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
