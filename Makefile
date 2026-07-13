.PHONY: all run test clean

BUILD_DIR := build
BINARY := $(BUILD_DIR)/nekobenchmark

all: $(BINARY)

$(BINARY): CMakeLists.txt src/main.cpp
	cmake -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Release
	cmake --build $(BUILD_DIR) --config Release

run: $(BINARY)
	./$(BINARY)

test: $(BINARY)
	ctest --test-dir $(BUILD_DIR) -C Release --output-on-failure

clean:
	cmake --build $(BUILD_DIR) --target clean
