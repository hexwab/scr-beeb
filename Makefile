PYTHON?=python
BEEBASM?=beebasm
EXO?=exomizer
UEFWALK=/home/HEx/uefwalk-1.50/
##########################################################################
##########################################################################

PNG2BBC_DEPS:=./bin/png2bbc.py ./bin/bbc.py
EXO_AND_ARGS=$(EXO) level -c -M256
EXO2=$(EXO) level

##########################################################################
##########################################################################

.PHONY:build
build:\
	./build/scr-beeb-title-screen.exo\
	./build/scr-beeb-menu.exo\
	./build/scr-beeb-credits.exo\
	./build/scr-beeb-hud.dat\
	./build/scr-beeb-preview.exo\
	./build/keys.mode7.exo\
	./build/trainer.mode7.exo\
	./build/scr-beeb-hof.exo\
	./build/track-preview.asm

	mkdir -p ./build
	$(PYTHON) bin/flames.py > build/flames-tables.asm
	$(PYTHON) bin/wheels.py > build/wheels-tables.asm
	$(PYTHON) bin/hud_font.py > build/hud-font-tables.asm
	$(PYTHON) bin/dash_icons.py > build/dash-icons.asm
	$(PYTHON) bin/horizon_table.py
	$(BEEBASM) -i scr-beeb.asm  -title "Stunt Car" -v > compile.txt
	$(EXO2) Title@0x3000 -o title.exo
	$(EXO2) Loader2@0x4e00 -o loader2.exo
	$(EXO2) Cart@0x8000 -o cart.exo
	$(EXO2) Kernel@0x8000 -o kernel.exo
	$(EXO2) Beebgfx@0x8000 -o beebgfx.exo
	$(EXO2) Beebmus@0x8800 -o beebmus.exo
	$(EXO2) Core@0x0e00 -o core.exo
	$(EXO2) Hazel@0xcb00 -o hazel.exo
	$(EXO2) Data@0x6000 -o data.exo
	$(BEEBASM) -i tapeloader.s -v > compile2.txt
	perl writeuef.pl >scr.uef
	$(UEFWALK)/uefwalk --output=bitstream --quiet scr.uef \
        | $(UEFWALK)/kleen/bitclean --text-input - \
        | sox -t raw -c 1 -L -b 16 -e signed -r 44100 - -t wav scr.wav

	cat compile.txt | grep -Evi '^\.' | grep -Evi '^    ' | grep -vi 'macro' | grep -vi 'saving file' | grep -vi 'safe to load to' | grep -Evi '^-+'

	$(PYTHON) bin/crc32.py scr-beeb.ssd

.PHONY:clean
clean:
	rm -Rf ./build

##########################################################################
##########################################################################

./build/scr-beeb-title-screen.exo:\
	./graphics/TitleScreen_BBC.png\
	$(PNG2BBC_DEPS)

	mkdir -p ./build
	$(PYTHON) bin/png2bbc.py --quiet -o build/scr-beeb-title-screen.dat --160 ./graphics/TitleScreen_BBC.png 2
	$(EXO_AND_ARGS) build/scr-beeb-title-screen.dat@0x3000 -o build/scr-beeb-title-screen.exo

##########################################################################
##########################################################################

./build/scr-beeb-menu.exo:\
	./graphics/scr-beeb-menu.png\
	$(PNG2BBC_DEPS)

	mkdir -p ./build
	$(PYTHON) bin/png2bbc.py --quiet -o build/scr-beeb-menu.dat --palette 0143 ./graphics/scr-beeb-menu.png 1
	$(EXO_AND_ARGS) build/scr-beeb-menu.dat@0x4000 -o build/scr-beeb-menu.exo

##########################################################################
##########################################################################

./build/scr-beeb-credits.exo:\
	./graphics/scr-beeb-credits.png

	mkdir -p ./build
	$(PYTHON) bin/png2bbc.py --quiet -o build/scr-beeb-credits.dat --160 ./graphics/scr-beeb-credits.png 2
	$(EXO_AND_ARGS) build/scr-beeb-credits.dat@0x3000 -o build/scr-beeb-credits.exo

##########################################################################
##########################################################################

./build/scr-beeb-hud.dat:\
	./graphics/scr-beeb-hud.png\
	$(PNG2BBC_DEPS)

	mkdir -p ./build
	$(PYTHON) bin/png2bbc.py --quiet -o build/scr-beeb-hud.dat -m build/scr-beeb-hud-mask.dat --160 --palette 0143 --transparent-output 3 --transparent-rgb 255 0 255 ./graphics/scr-beeb-hud.png 5

##########################################################################
##########################################################################

./build/scr-beeb-preview-bg.exo\
./build/scr-beeb-preview.exo\
./build/track-preview.asm\
	:\
	./graphics/scr-beeb-preview.png\
	./build/scr-beeb-hud.dat\
	./bin/track_preview.py\
	./bin/bbc.py

	$(PYTHON) bin/track_preview.py > build/track-preview.asm
	$(EXO_AND_ARGS) build/scr-beeb-preview.dat@0x4000 -o build/scr-beeb-preview.exo
	$(EXO_AND_ARGS) build/scr-beeb-preview-bg.dat@0x6280 -o build/scr-beeb-preview-bg.exo

##########################################################################
##########################################################################

./build/keys.mode7.exo:\
	./data/keys.mode7.txt\
	./bin/teletext2bin.py

	$(PYTHON) bin/teletext2bin.py data/keys.mode7.txt build/keys.mode7.bin
	$(EXO_AND_ARGS) build/keys.mode7.bin@0x7c00 -o build/keys.mode7.exo

##########################################################################
##########################################################################

./build/trainer.mode7.exo:\
	./data/trainer.mode7.txt\
	./bin/teletext2bin.py

	$(PYTHON) bin/teletext2bin.py data/trainer.mode7.txt build/trainer.mode7.bin
	$(EXO_AND_ARGS) build/trainer.mode7.bin@0x7c00 -o build/trainer.mode7.exo

##########################################################################
##########################################################################

./build/scr-beeb-hof.exo:\
	./graphics/HallFame_BBC.png

	$(PYTHON) bin/png2bbc.py --quiet -o build/scr-beeb-hof.dat --palette 0143 ./graphics/HallFame_BBC.png 1
	$(EXO_AND_ARGS) build/scr-beeb-hof.dat@0x4000 -o build/scr-beeb-hof.exo

##########################################################################
##########################################################################

.PHONY:b2_test
b2_test:
	-$(MAKE) _b2_test

.PHONY:_b2_test
_b2_test:
	curl -G 'http://localhost:48075/reset/b2' --data-urlencode "config=Master 128 (MOS 3.20)"
	curl -H 'Content-Type:application/binary' --upload-file 'scr-beeb.ssd' 'http://localhost:48075/run/b2?name=scr-beeb.ssd'

##########################################################################
##########################################################################

.PHONY:tom_beeblink
tom_beeblink: DEST=~/beeb/beeb-files/stuff
tom_beeblink:
	cp ./scr-beeb.ssd $(DEST)/ssds/0/s.scr-beeb
	touch $(DEST)/ssds/0/s.scr-beeb.inf

	rm -Rf $(DEST)/scr-beeb/0
	ssd_extract --not-emacs -o $(DEST)/scr-beeb/0/ -0 ./scr-beeb.ssd
