use v6;
use GGE::Exp;

class GGE::Exp::RegexContainer is GGE::Exp {
}

class GGE::TreeSpider {
    has GGE::Exp $!top;
    has Str      $!target;
    has Int      $!pos;
    has Bool     $!iterate-positions;

    submethod BUILD(GGE::Exp :$regex!, Str :$!target!, :$pos!) {
        $!top = GGE::Exp::RegexContainer.new();
        $!top[0] = $regex;
        # RAKUDO: Smartmatch on type yields an Int, must convert to Bool
        #         manually. [perl #71462]
        if $!iterate-positions = ?($pos ~~ Whatever) {
            $!pos = 0;
        }
        else {
            $!pos = $pos;
        }
    }

    method crawl(:$debug) {
        GGE::Match.new(:$!target, :from(0), :to(-2));
    }
}
