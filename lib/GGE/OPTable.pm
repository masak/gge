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
            'prefix:'        => { expect => 0x0101, arity => 1 },
            'infix:'         => { expect => 0x0102, arity => 2 },
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
            if $top<syncat> == GGE_OPTABLE_CLOSE {
                $top = pop @tokenstack;
                $oper = pop @operstack;
            }
            my @temp;
            my $arity = $top<arity>;
            for ^$arity {
                @temp.push(pop(@termstack));
            }
            if ?@temp[0] {
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
        };
        while $pos < $text.chars {
            my $wspos = $pos;
            $pos++ while $text.substr($pos, 1) ~~ /\s/;
            my $nows = $pos != $wspos;
            my $last_pos = $pos;
            my $stop_matching = False;
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
                                if $topcat < GGE_OPTABLE_CIRCUMFIX {
                                    reduce;
                                }
                                $top = @tokenstack[*-1];
                                if $top<keyclose> ne $key {
                                    $stop_matching = True;
                                    last;
                                }
                                --$circumnest;
                            }
                            elsif $topcat >= GGE_OPTABLE_POSTCIRCUMFIX {
                                ++$circumnest;
                                # go directly to shift
                            }
                            else {
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
                        }
                        shift_oper($name, $key);
                        $found_oper = True;
                        last;
                    }
                }
                last if $found_oper || $stop_matching;
                last if $key eq '';
                $key .= chop();
            }
            if $stop_matching || $last_pos == $pos {
                last;
            }
            $m.to = $pos;
        }
        if !@termstack || $circumnest > 0 {
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
        if @termstack {
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
