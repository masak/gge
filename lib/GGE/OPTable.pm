use v6;

use GGE::Match;

class GGE::OPTable {
    # RAKUDO: Must define these within the class for them to be visible.
    constant GGE_OPTABLE_EXPECT_TERM = 0x01;
    constant GGE_OPTABLE_EXPECT_OPER = 0x02;

    has %!tokens;

    method newtok($name, *%opts) {
        %!tokens{$name} = %opts;
    }

    method parse($text, *%opts) {
        my $m = GGE::Match.new(:target($text));
        my $pos = 0;
        my (@termstack, @tokenstack, @operstack);
        my $expect = GGE_OPTABLE_EXPECT_TERM;
        while $pos < $text.chars {
            my $last_pos = $pos;
            for %!tokens.keys -> $key {
                if %!tokens{$key}.exists('parsed') {
                    my $routine = %!tokens{$key}<parsed>;
                    my $oper = $routine($m);
                    if $oper.to > $pos {
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
                        my $op = GGE::Match.new(:from($pos),
                                                :to($pos + $name.chars),
                                                :target($text));
                        $op<type> = $key;
                        push @tokenstack, $op;
                        push @operstack, $op;
                        $pos = $op.to;
                        $expect = GGE_OPTABLE_EXPECT_TERM;
                        last;
                    }
                }
            }
            $m.to = $pos;
            return $m if $last_pos == $pos;
        }
        while @operstack {
            my $top = pop @tokenstack;
            my $oper = pop @operstack;
            my @temp = pop(@termstack), pop(@termstack);
            $oper.push( @temp[1] );
            $oper.push( @temp[0] );
            push @termstack, $oper;
        }
        $m<expr> = @termstack[0];
        $m
    }
}
