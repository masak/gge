use v6;

use GGE::Exp;

class GGE::Cursor;

has $.is-active;
has $.succeeded;

has @!terms;
has $!termindex;
has $.is-backtracking;

has $!target;

has @!marks;

method new(@terms, $target) {
    die 'Must have at least one term'
        unless @terms;

    self.bless(*, :@terms, :$target, :is-active, :termindex(0));
}

method current-term() {
    @!terms[$!termindex];
}

method push($pos) {
    die 'Can only push on a quantifier'
        unless $.current-term ~~ GGE::Exp::Quant;

    @!marks.push: [$!termindex, sub {
        my $to = $pos;
        my $reps = 0;
        my &step;
        given $.current-term {
            while $reps < .min {
                return undef unless .expr.matches($!target, $to);
                ++$reps;
            }
            my @positions;
            if .type eq 'greedy' {
                while ++$reps <= .max {
                    # RAKUDO: Have to add zero (or eqiv) to the variable
                    @positions.push($to + 0);
                    last unless .expr.matches($!target, $to);
                }
            }
            &step = .ratchet
                ?? { undef }
                !!
            {
                if .type eq 'eager' {
                    ++$reps <= .max && .expr.matches($!target, $to)
                      ?? ($to, &step)
                      !! undef;
                }
                elsif .type eq 'greedy' {
                    @positions
                        ?? (@positions.pop(), &step)
                        !! undef;
                }
            };
        }
        $to, &step
    }];
}

method mark() { @!marks[*-1] }

method get() {
    (my $to), $.mark[1] = $.mark[1].();
    if !defined $.mark[1] {
        @!marks.pop;
    }
    return $to;
}

method proceed() {
    $!is-backtracking = False;
    if ++$!termindex >= @!terms {
        $!is-active = False;
        $!succeeded  = True;
    }
}

method backtrack() {
    $!is-backtracking = True;
    if @!marks {
        $!termindex = $.mark[0];
    }
    else {
        $!is-active = False;
        $!succeeded = False;
    }
}
