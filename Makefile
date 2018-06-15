SHELL_DIR:=$(shell pwd)
EBIN_DIR:=$(SHELL_DIR)/ebin
SRC_DIR:=$(SHELL_DIR)/src
INCLUDE:=$(SHELL_DIR)/include

ERL:=erl

erl:make cp
make:
	$(ERL) -pa $(EBIN_DIR) -I $(EBIN_DIR) -noinput \
		-eval "case make:all() of up_to_date -> halt(0); error -> halt(1) end."

cp:
	@cp $(SRC_DIR)/badpool.app.src $(EBIN_DIR)/badpool.app

clean:
	rm -f ebin/*.beam
