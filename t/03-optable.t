use v6;
use Test;

use GGE::OPTable;
use GGE::Match;
use GGE::Perl6Regex;

my GGE::OPTable $optable .= new;

# RAKUDO: I initially called the variable &ident because that's nicer, but
#         that triggered the Parrot bug wherein methods in a class collide
#         with routines outside of it. So $ident it is.
my $ident = &GGE::Match::ident;
my $arrow = GGE::Perl6Regex.new("'->' <ident>");
for ['infix:+',           precedence => '='                           ],
    ['infix:-',           equiv      => 'infix:+'                     ],
    ['infix:*',           tighter    => 'infix:+'                     ],
    ['infix:/',           equiv      => 'infix:*'                     ],
    ['infix:**',          tighter    => 'infix:*'                     ],
    ['infix:==',          looser     => 'infix:+'                     ],
    ['infix:=',           looser     => 'infix:==', :assoc<right>     ],
    ['infix:,',           tighter    => 'infix:=',  :assoc<list>      ],
    ['infix:;',           looser     => 'infix:=',  :assoc<list>      ],
    ['prefix:++',         tighter    => 'infix:**'                    ],
    ['prefix:--',         equiv      => 'prefix:++'                   ],
    ['postfix:++',        equiv      => 'prefix:++'                   ],
    ['postfix:--',        equiv      => 'prefix:++'                   ],
    ['prefix:-',          equiv      => 'prefix:++'                   ],
    ['term:',             tighter    => 'prefix:++', :parsed($ident)  ],
    ['circumfix:( )',     equiv      => 'term:'                       ],
    ['circumfix:[ ]',     equiv      => 'term:'                       ],
    ['postcircumfix:( )', looser     => 'term:', :nullterm,  :nows    ],
    ['postcircumfix:[ ]', equiv      => 'postcircumfix:( )', :nows    ]
-> @args { my ($name, %opts) = @args; $optable.newtok($name, |%opts) }

optable_output_is( 'a',     'term:a',                                   'Simple term' );
optable_output_is( 'a+b',   'infix:+(term:a, term:b)',                  'Simple infix' );
optable_output_is( 'a-b',   'infix:-(term:a, term:b)',                  'Simple infix' );
optable_output_is( 'a+b+c', 'infix:+(infix:+(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a+b-c', 'infix:-(infix:+(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a-b+c', 'infix:+(infix:-(term:a, term:b), term:c)', 'left associativity' );

optable_output_is( 'a+b*c', 'infix:+(term:a, infix:*(term:b, term:c))', 'tighter precedence' );
optable_output_is( 'a*b+c', 'infix:+(infix:*(term:a, term:b), term:c)', 'tighter precedence' );

optable_output_is( 'a/b/c', 'infix:/(infix:/(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a*b/c', 'infix:/(infix:*(term:a, term:b), term:c)', 'left associativity' );
optable_output_is( 'a/b*c', 'infix:*(infix:/(term:a, term:b), term:c)', 'left associativity' );

optable_output_is( 'a=b*c', 'infix:=(term:a, infix:*(term:b, term:c))', 'looser precedence' );

optable_output_is( 'a=b=c', 'infix:=(term:a, infix:=(term:b, term:c))', 'right associativity' );

optable_output_is(
    'a=b,c,d+e',
    'infix:=(term:a, infix:,(term:b, term:c, infix:+(term:d, term:e)))',
    'list associativity'
);

optable_output_is( 'a b',     'term:a (pos=1)', 'two terms in sequence' );
optable_output_is( 'a = = b', 'term:a (pos=1)', 'two opers in sequence' );
optable_output_is( 'a +',     'term:a (pos=1)', 'infix missing rhs' );

optable_output_is( 'a++', 'postfix:++(term:a)', 'postfix' );
optable_output_is( 'a--', 'postfix:--(term:a)', 'postfix' );
optable_output_is( '++a', 'prefix:++(term:a)',  'prefix' );
optable_output_is( '--a', 'prefix:--(term:a)',  'prefix' );

optable_output_is( '-a',  'prefix:-(term:a)',   'prefix ltm');
optable_output_is( '->a', 'term:->a',           'prefix ltm');

optable_output_is(
    'a*(b+c)',
    'infix:*(term:a, circumfix:( )(infix:+(term:b, term:c)))',
    'circumfix parens'
);
optable_output_is(
    'a*b+c)+4',
    'infix:+(infix:*(term:a, term:b), term:c) (pos=5)',
    'extra close paren'
);
optable_output_is( '  )a*b+c)+4', 'failed', 'only close paren' );
optable_output_is( '(a*b+c',      'failed', 'missing close paren' );
optable_output_is( '(a*b+c]',     'failed', 'mismatch close paren' );

optable_output_is( 'a+++--b', 'infix:+(postfix:++(term:a), prefix:--(term:b))', 'mixed tokens' );

optable_output_is( '=a+4', 'failed', 'missing lhs term' );

optable_output_is( 'a(b,c)', 'postcircumfix:( )(term:a, infix:,(term:b, term:c))',
    'postcircumfix' );
optable_output_is( 'a (b,c)', 'term:a (pos=1)', 'nows on postcircumfix' );

optable_output_is( 'a()', 'postcircumfix:( )(term:a, null)', 'nullterm in postcircumfix' );
optable_output_is( 'a[]', 'term:a (pos=1)', 'nullterm disallowed' );

optable_output_is(
    '(a=b;c;d)',
    'circumfix:( )(infix:;(infix:=(term:a, term:b), term:c, term:d))',
    'loose list associativity in circumfix'
);

optable_output_is(
    '(a;b);d',
    'circumfix:( )(infix:;(term:a, term:b)) (pos=5)',
    'top-level stop token'
);

optable_output_is( 'a,b;c', 'infix:,(term:a, term:b) (pos=3)', 'top-level stop token' );

sub optable_output_is($test, $expected, $msg) {
    my $output;
    if $optable.parse($test, :stop(' ;')) -> $match {
        $output = tree($match<expr>);
        if $match.to != $test.chars {
            $output ~= " (pos={$match.to})";
        }
    }
    else {
        $output = 'failed';
    }

    is $output, $expected, $msg;
}

sub tree($match) {
    return 'null' if $match ~~ '';
    my $r = $match<type>;
    given $match<type> {
        # RAKUDO: Removing the semicolon below causes a runtime error
        when 'term:'   { ; $r ~= $match };
        $r ~= '(' ~ (join ', ', map { tree($_) }, $match.llist) ~ ')';
    }
    return $r;
}

done_testing;
