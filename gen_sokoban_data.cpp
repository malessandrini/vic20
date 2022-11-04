#include <cstdint>
#include <string>
#include <vector>
#include <iostream>


struct Level {
	Level(const std::vector<std::string>&);
	std::vector<uint8_t> cells;
	unsigned rows, columns;
	void static read_file(const std::string &filename);  // throws
	static constexpr uint8_t wall = 1, goal = 2, stone = 4, man = 8;
	unsigned num_stones() const;
};
