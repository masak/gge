use v6;

use GGE::Match;

class GGE::OPTable {
    has %!tokens;

    method newtok($name, *%opts) {
        %!tokens{$name} = %opts;
    }

    method parse($text, *%opts) {
        my $m = GGE::Match.new(:target($text));
        my $pos = 0;
        my @stack;
        for %!tokens.keys -> $key {
            if %!tokens{$key}.exists('parsed') {
                my $routine = %!tokens{$key}<parsed>;
                my $oper = $routine($m);
                $pos = $oper.to;
                $oper<type> = $key;
                push @stack, $oper;
            }
        }
        $m<expr> = @stack.pop;
        $m.to = $pos;
        $m
    }
}
