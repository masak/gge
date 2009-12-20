PERL6=/Users/masak/work/hobbies/parrot/languages/rakudo/perl6
RAKUDO_DIR=/Users/masak/work/hobbies/parrot/languages/rakudo
PERL6LIB='/Users/masak/gwork/gge/lib:/Users/masak/gwork/gge/lib:$(RAKUDO_DIR)'

SOURCES=lib/GGE/Match.pm lib/GGE/Exp.pm lib/GGE/TreeSpider.pm \
        lib/GGE/OPTable.pm lib/GGE/Perl6Regex.pm lib/GGE.pm

PIRS=$(SOURCES:.pm=.pir)

all: $(PIRS)

%.pir: %.pm
	env PERL6LIB=$(PERL6LIB) $(PERL6) --target=pir --output=$@ $<

clean:
	rm -f $(PIRS)

test: all
	env PERL6LIB=$(PERL6LIB) prove -e '$(PERL6)' -r --nocolor t/
