#include <cstdint>
#include <string>
#include <vector>
#include <iostream>
#include <cstdio>
#include <cassert>
#include <algorithm>
#include <sstream>
#include <set>

struct Level {
	Level(const std::vector<std::string>&);
	std::vector<uint8_t> cells;
	unsigned rows, columns;
	unsigned total() const { return rows * columns; }
	static std::vector<Level> read_data(const std::string &);  // throws
	static constexpr uint8_t wall = 1, goal = 2, stone = 4, man = 8;
	unsigned num_stones() const { return std::count_if(cells.begin(), cells.end(), [](auto c){ return c & stone; }); }
	bool fits() const;
	std::vector<uint8_t> encoded_parts() const;
};

extern const std::string microban;


int main() {
	auto levels = Level::read_data(microban);
	std::cout << "Levels: " << levels.size() << std::endl;
	//for (int i = 0; i < levels.size(); ++i)
	//	std::cout << i + 1 << "\t" << levels[i].rows << "x" << levels[i].columns << "\t" << (levels[i].total()) << "\t" << levels[i].num_stones() << "\n";
	for (int i = 0; i < levels.size(); ++i)
		if (!levels[i].fits()) std::cout << "discard: " <<  (i + 1) << "\n";
	std::cout << "max rows, cols, tot: "
		<< std::max_element(levels.cbegin(), levels.cend(), [](const auto &a, const auto &b){ return (a.fits() ? a.rows : 0) < (b.fits() ? b.rows : 0); })->rows << " "
		<< std::max_element(levels.cbegin(), levels.cend(), [](const auto &a, const auto &b){ return (a.fits() ? a.columns : 0) < (b.fits() ? b.columns : 0); })->columns << " "
		<< std::max_element(levels.cbegin(), levels.cend(), [](const auto &a, const auto &b){ return (a.fits() ? a.total() : 0) < (b.fits() ? b.total() : 0); })->total() << "\n";
	std::vector<uint8_t> all_levels;
	std::set<std::vector<uint8_t>> code_set;
	std::vector<std::vector<uint8_t>> codes;
	for (auto const &l: levels)
		if (l.fits()) {
			const auto enc = l.encoded_parts();
			// unique code for every level generated from level data, found experimentally as follows:
			// last 6 bytes, 4 bits for each byte in proper position -> can be written as 6 letters or 6 hex digits
			std::vector<uint8_t> code(enc.cend() - 6, enc.end());
			for (auto &c: code) c = (c & 0b00111100) >> 2;
			if (!code_set.insert(code).second) std::cout << "WARNING: duplicated code!" << std::endl;
			codes.push_back(code);
			//
			all_levels.insert(all_levels.end(), enc.begin(), enc.end());
		}
	for (int i = 0; i < codes.size(); ++i) {
		std::cout << i + 1 << "\t";
		for (auto const c: codes[i]) std::cout << char('A' + c);
		std::cout << std::endl;
	}
	std::cout << "Encoded size: " << all_levels.size() << "\n" << std::endl;
	//FILE *f = fopen("aaaaa", "wb");
	//fwrite(all_levels.data(), 1, all_levels.size(), f);
	//fclose(f);
	for (unsigned i = 0; i < all_levels.size(); i += 32) {
		printf("\thex ");
		for (unsigned j = 0; j < std::min((size_t)32, all_levels.size() - i); ++j)
			printf("%02X", all_levels[i + j]);
		printf("\n");
	}
}


Level::Level(const std::vector<std::string> &lines) {
	rows = lines.size();
	assert(rows > 2);
	columns = std::max_element(lines.begin(), lines.end(), [](auto const &a, auto const &b){ return a.size() < b.size(); })->size();
	// TODO: make columns a power of 2 to better compute position from 2D values?
	assert(columns > 2);
	cells.resize(rows * columns, 0);
	uint8_t *p = cells.data();
	for (auto const &l: lines) {
		for (char c: l) {
			switch (c) {
			case ' ':
				++p;
				break;
			case '#':
				*p++ = wall;
				break;
			case '.':
				*p++ = goal;
				break;
			case '$':
				*p++ = stone;
				break;
			case '*':
				*p++ = stone | goal;
				break;
			case '@':
				*p++ = man;
				break;
			case '+':
				*p++ = man | goal;
				break;
			default:
				throw std::runtime_error("invalid character");
			}
		}
		p += columns - l.size();
	}
}


std::vector<Level> Level::read_data(const std::string &def) {
	std::istringstream f(def);
	std::string line;
	std::vector<Level> collection;
	std::vector<std::string> curr_level;
	uint32_t row_num = 0;
	while (std::getline(f, line)) {
		++row_num;
		while (line.size() && line[line.size() - 1] == '\r') line.resize(line.size() - 1);
		if (!line.size()) {
			// end of a level
			if (curr_level.size()) collection.push_back(Level(curr_level));
			curr_level.clear();
		}
		else curr_level.push_back(line);
	}
	// last \n at end of file can be missing
	if (curr_level.size()) {
		collection.push_back(Level(curr_level));
	}
	return collection;
}


bool Level::fits() const {
	return rows <= 22 && columns <= 22 && (rows * columns) <= 255;
}


std::vector<uint8_t> Level::encoded_parts() const {
	std::vector<uint8_t> e(4 + (cells.size() + 7) / 8);
	e[1] = rows;
	e[2] = columns;
	// man position
	auto i = std::find_if(cells.begin(), cells.end(), [](auto v){ return v & man; });
	e[3] = i - cells.begin();
	auto p = e.begin() + 3;
	for (int i = 0; i < cells.size(); ++i) {
		if (i % 8) {
			*p <<= 1;
			if (cells[i] & wall) *p |= 1;
		}
		else *++p = (cells[i] & wall) ? 1 : 0;
	}
	// last bits (if not exact multiple of 8) must be shifted to the left
	unsigned n = (cells.size() % 8) ? 8 - (cells.size() % 8) : 0;
	for (unsigned i = 0; i < n; ++i) *p <<= 1;
	unsigned st = num_stones();
	e.push_back(st);
	for (auto i = cells.begin(); i != cells.end(); ++i)
		if (*i & stone) e.push_back(i - cells.begin());
	for (auto i = cells.begin(); i != cells.end(); ++i)
		if (*i & goal) e.push_back(i - cells.begin());
	assert(e.size() < 256);
	e[0] = e.size();
	return e;
}




const std::string microban(
R"(
####
# .#
#  ###
#*@  #
#  $ #
#  ###
####


######
#    #
# #@ #
# $* #
# .* #
#    #
######


  ####
###  ####
#     $ #
# #  #$ #
# . .#@ #
#########


########
#      #
# .**$@#
#      #
#####  #
    ####


 #######
 #     #
 # .$. #
## $@$ #
#  .$. #
#      #
########


###### #####
#    ###   #
# $$     #@#
# $ #...   #
#   ########
#####


#######
#     #
# .$. #
# $.$ #
# .$. #
# $.$ #
#  @  #
#######


  ######
  # ..@#
  # $$ #
  ## ###
   # #
   # #
#### #
#    ##
# #   #
#   # #
###   #
  #####


#####
#.  ##
#@$$ #
##   #
 ##  #
  ##.#
   ###


      #####
      #.  #
      #.# #
#######.# #
# @ $ $ $ #
# # # # ###
#       #
#########


  ######
  #    #
  # ##@##
### # $ #
# ..# $ #
#       #
#  ######
####


#####
#   ##
# $  #
## $ ####
 ###@.  #
  #  .# #
  #     #
  #######


####
#. ##
#.@ #
#. $#
##$ ###
 # $  #
 #    #
 #  ###
 ####


#######
#     #
# # # #
#. $*@#
#   ###
#####


     ###
######@##
#    .* #
#   #   #
#####$# #
    #   #
    #####


 ####
 #  ####
 #     ##
## ##   #
#. .# @$##
#   # $$ #
#  .#    #
##########


#####
# @ #
#...#
#$$$##
#    #
#    #
######


#######
#     #
#. .  #
# ## ##
#  $ #
###$ #
  #@ #
  #  #
  ####


########
#   .. #
#  @$$ #
##### ##
   #  #
   #  #
   #  #
   ####


#######
#     ###
#  @$$..#
#### ## #
  #     #
  #  ####
  #  #
  ####


####
#  ####
# . . #
# $$#@#
##    #
 ######


#####
#   ###
#. .  #
#   # #
## #  #
 #@$$ #
 #    #
 #  ###
 ####


#######
#  *  #
#     #
## # ##
 #$@.#
 #   #
 #####


# #####
  #   #
###$$@#
#   ###
#     #
# . . #
#######


 ####
 #  ###
 # $$ #
##... #
#  @$ #
#   ###
#####


 #####
 # @ #
 #   #
###$ #
# ...#
# $$ #
###  #
  ####


######
#   .#
# ## ##
#  $$@#
# #   #
#.  ###
#####


#####
#   #
# @ #
# $$###
##. . #
 #    #
 ######


     #####
     #   ##
     #    #
 ######   #
##     #. #
# $ $ @  ##
# ######.#
#        #
##########


####
#  ###
# $$ #
#... #
# @$ #
#   ##
#####


  ####
 ##  #
##@$.##
# $$  #
# . . #
###   #
  #####


 ####
##  ###
#     #
#.**$@#
#   ###
##  #
 ####


#######
#. #  #
#  $  #
#. $#@#
#  $  #
#. #  #
#######


  ####
###  ####
#       #
#@$***. #
#       #
#########


  ####
 ##  #
 #. $#
 #.$ #
 #.$ #
 #.$ #
 #. $##
 #   @#
 ##   #
  #####


####
#  ############
# $ $ $ $ $ @ #
# .....       #
###############


      ###
##### #.#
#   ###.#
#   $ #.#
# $  $  #
#####@# #
    #   #
    #####


##########
#        #
# ##.### #
# # $$ . #
# . @$## #
#####    #
    ######


#####
#   ####
# # # .#
#    $ ###
### #$.  #
#   #@   #
# # ######
#   #
#####


 #####
 #   #
##   ##
# $$$ #
# .+. #
#######


#######
#     #
#@$$$ ##
#  #...#
##    ##
 ######


   ####
   #  #
   #@ #
####$.#
#   $.#
# # $.#
#    ##
######


     ####
     # @#
     #  #
###### .#
#   $  .#
#  $$# .#
#    ####
###  #
  ####


#####
#@$.#
#####


######
#... #
#  $ #
# #$##
#  $ #
#  @ #
######


 ######
##    #
#  ## #
# # $ #
#  * .#
## #@##
 #   #
 #####


  #######
###     #
# $ $   #
# ### #####
# @ . .   #
#   ###   #
##### #####


######
#  @ #
#  # ##
# .#  ##
# .$$$ #
# .#   #
####   #
   #####


######
# @  #
# $# #
# $  #
# $ ##
### ####
 #  #  #
 #...  #
 #     #
 #######


  ####
###  #####
#  $  @..#
# $    # #
### #### #
  #      #
  ########


####
#  ###
#    ###
#  $*@ #
### .# #
  #    #
  ######


  ####
### @#
#  $ #
#  *.#
#  *.#
#  $ #
###  #
  ####


 #####
##. .##
# * * #
#  #  #
# $ $ #
## @ ##
 #####


      ######
      #    #
  ##### .  #
###  ###.  #
# $  $  . ##
# @$$ # . #
##    #####
 ######


########
# @ #  #
#      #
#####$ #
    #  ###
 ## #$ ..#
 ## #  ###
    ####


#####
#   ###
#  $  #
##* . #
 #   @#
 ######


  ####
  #  #
  #@ #
  #  #
### ####
#    * #
#  $   #
#####. #
    ####


####
#  ####
#.*$  #
# .$# #
## @  #
 #   ##
 #####


############
#          #
# ####### @##
# #         #
# #  $   #  #
# $$ #####  #
###  # # ...#
  #### #    #
       ######


 #########
 #       #
##@##### #
#  #   # #
#  #   $.#
#  ##$##.#
##$##  #.#
#   $  #.#
#   #  ###
########


########
#      #
# #### #
# #...@#
# ###$###
# #     #
#  $$ $ #
####   ##
   #.###
   ###


   ##########
####    ##  #
#  $$$....$@#
#      ###  #
#   #### ####
#####


#####   ####
#   ##### .#
#       $  ########
###  #### .$    @ #
  #  #  #  ####   #
  ####  ####  #####


 ######
##    #
#   $ #
#  $$ #
### .#####
  ##.# @ #
   #.  $ #
   #. ####
   ####


  ######
  #    #
  #  $ #
 ####$ #
## $ $ #
#....# ##
#     @ #
##  #   #
 ########


   ###
   #@#
 ###$###
##  .  ##
#  # #  #
# #   # #
# #   # #
# #   # #
#  # #  #
## $ $ ##
 ##. .##
  #   #
  #   #
  #####


#####
#   ##
# #  #
#@$*.##
##  . #
 # $# #
 ##   #
  #####


 ####
 #  ######
##    $  #
# .# $   #
# .#$#####
# .@ #
######


####  ####
#  ####  #
#  #  #  #
#  #    $##
#  . .#$  #
#@ ## # $ #
#   . #   #
###########


#####
# @ ####
#      #
# $ $$ #
##$##  #
#   ####
# ..  #
##..  #
 ###  #
   ####


###########
#     #   ###
# $@$ # .  .#
# ## ### ## #
# #       # #
# #   #   # #
# ######### #
#           #
#############


  ####
 ##  #####
 #  $  @ #
 #  $#   #
#### #####
#  #   #
#    $ #
# ..#  #
#  .####
#  ##
####


####
#  #####
# $$ $ #
#      #
## ## ##
#...#@#
# ### ##
#      #
#  #   #
########


 ####
 #  #######
 #$ @#   .#
## #$$   .#
#  $  ##..#
#   # #####
###   #
  #####


 #######
## ....##
#   ######
#   $ $ @#
###  $ $ #
  ###    #
    ######


 #####
##   #
#    #####
#  #.#   #
#@ #.# $ #
#  #.#  ##
#    #  #
##  ##$$#
 ##     #
  #  ####
  ####


##########
# @ .... #
#   ####$##
## #  $ $ #
 # $      #
 #   ######
 #####


 #######
##     ##
#  $ $  #
# $ $ $ #
## ### ####
 #@  .....#
 ##     ###
  #######


 #########
 #    #  #
## $#$#  #
#  .$.@  #
#  .#    #
##########


####
#  #######
#  . ## .#
# $#    .#
## ## # .#
 #    #  #
 #### #  #
  # @$ ###
  # $$ #
  #    #
  ######


 #####
 #   #
 # . #
## * #
#  *##
#  @##
## $ #
 #   #
 #####


#####
#   ###
# .   ##
##*#$  #
# .# $ #
# @## ##
#     #
#######


######
#    ##
# $ $ ##
## $$  #
 # #   #
 # ## ##
 #  . .#
 # @. .#
 #  ####
 ####


########
#  ... #
#  ### ##
#  # $  #
## #@$  #
 # # $  #
 # ### #####
 #         #
 #   ###   #
 ##### #####


       ####
 #######  #
 # $      #
 #   $ $  #
 # ########
## # .  #
#  # #  #
#  @ . ##
## # # #
 #   . #
 #######


    ####
  ###  ##
 ## $   #
## $  # #
# @#$$  #
# ..  ###
# ..###
#####


     ####
######  #
#       #
#  ... .#
##$######
# $  #
#   $###
##  $  #
 ## @  #
  ######


     ####
 # ###  #
 # #    #
 # #  # #
 # #$ #.#
 # #  # # #
 # #$ #.# #
   #  # # #
####$ #.# #
# @     # #
#   #  ## #
########


##########
#   ##   #
# $  $@# #
#### # $ #
   #.#  ##
 # #.# $#
 # #.   #
 # #.   #
   ######


 ########
 #  @   #
 # $  $ #
### ## ###
#  $..$  #
#   ..   #
##########


###########
#    .##  #
# $$@..$$ #
#   ##.   #
###########


  ####
  #  #    #####
  #  #    #   #
  #  ######.# #
####  $    .  #
#   $$# ###.# #
#   #   # #   #
######### #@ ##
          #  #
          ####


 #########
##   #   ##
#    #    #
#  $ # $  #
#   *.*   #
####.@.####
#   *.*   #
#  $ # $  #
#    #    #
##   #   ##
 #########


#########
# @ #   #
# $ $   #
##$### ##
#  ...  #
#   #   #
######  #
     ####


########
#@     #
# .$$. #
# $..$ #
# $..$ #
# .$$. #
#      #
########


  ######
  #    #
  #    #
#####  #
#   #.#####
#   $@$   #
#####.#   #
   ## ## ##
   #   $.#
   #   ###
   #####


   ####
   #  ########
#### $ $.....#
#   $   ######
#@### ###
#  $  #
# $ # #
## #  #
 #    #
 ######


#####
#   ## ####
#  $ ### .#
# $   $  .#
## $#####.# ####
# $  # # .###  #
#    # # .#  @ #
###  # #       #
  #### ##     ##
        #######


               #####
               #   #
#######  ####### # #
#     #  #  #      #
#  @  ####  #     ####
#  #    ....## ####  #
#    ##### ## $$ $ $ #
######   #           #
         #  ##########
         ####


#######
# @#  #
#.$   #
#. # $##
#.$#   #
#. # $ #
#  #   #
########


  #####
  #   #
  # # #######
  #  *  #   #
  ## ##   # #
  #     #*  #
### # # # ###
#  *#$+   #
# #   ## ##
#   #  *  #
####### # #
      #   #
      #####


###########
#....#    #
#  #   $$ #
#  @  ##  #
#     ##$ #
######  $ #
     #    #
     ######


  #####
  # . ##
### $  #
# . $#@#
# #$ . #
#  $ ###
## . #
 #####


    #####
#####   #
#    $  #
#  $#$#@#
### #   #
  # ... #
  ###  ##
    #  #
    ####


 #### ####
##  ###  ##
#   # #   #
#  *. .*  #
###$   $###
 #   @   #
###$   $###
#  *. .*  #
#   # #   #
##  ###  ##
 #### ####


 ########
 #      #
 #@   $ #
## ###$ #
# .....###
# $ $ $  #
###### # #
     #   #
     #####


########
#      #
# $*** #
# *  * #
# *  * #
# ***. #
#     @#
########


####     #####
#  ###   #   ##
#    #   #$ $ #
#..# ##### #  #
#  @    # $ $ #
#..#         ##
##   #########
 #####


  #######
# #     #
# # # # #
  # @ $ #
### ### #
#   ### #
# $  ##.#
## $  #.#
 ## $  .#
# ## $#.#
## ## #.#
### #   #
### #####


  ####
  #  #
  # $####
###. .  #
# $ # $ #
#  . .###
####$ #
   # @#
   ####


######
#    ####
#    ...#
#    ...#
######  #
  #  #  #
  # $$ ##
  # @$  #
  # $$  #
  ## $# #
   #    #
   ######


 #####
##   ####
#  $$$  #
# #   $ #
#   $## ##
###  #.  #
  #  #   #
 ##### ###
 #   # ##
 # @....#
 #      #
 #   #  #
 ########


   #####
  ##   #
###  # #
#    . #
#  ## #####
#  . . #  ##
#  # @ $   ###
#####. #  $  #
    ####  $  #
       ## $ ##
        #  ##
        #  #
        ####


######
#    ###
#  # $ #
#  $ @ #
## ## #####
#  #......#
# $ $ $ $ #
##   ######
 #####


    #####
#####   ####
#     #    #
#  #.....  #
##  ## # ###
 #$$@$$$ #
 #     ###
 #######


     #####
   ###   #
####.....#
# @$$$$$ #
#     # ##
#####   #
    #####


 #### ####
 #  ###  ##
 #      @ #
##..###   #
#      #  #
#...#$  # #
# ## $$ $ #
#  $    ###
####  ###
   ####


 #####
##   ##
#  $  ##
# $ $  ##
###$# . ##
  # # .  #
 ## ##.  #
 # @  . ##
 #   #  #
 ########


  ######
  #    ##
 ## ##  #
 # $$ # #
 # @$ # #
 #    # #
#### #  #
#  ... ##
#     ##
#######


      ####
#######  #
# $      ##
# $#####  #
#  @#  #  #
## ##..   #
#  # ..####
# $  ###
# $###
#  #
####


 ######
 # .  #
##$.# #
#  *  #
# ..###
##$ # #####
## ## #   #
#  #### # #
#   @ $ $ #
##  #     #
 ##########


#####
#   ###
# #$  #
# $   #
# $ $ #
# $#  #
#  @###
## ########
#      ...#
#         #
########..#
       ####


########
#      #
# $ $$ ########
##### @##. .  #
    #$  # .   #
    #   #. . ##
    #$# ## # #
    #        #
    #  ###  ##
    #  # ####
    ####


##############
#      #     #
# $@$$ # . ..#
## ## ### ## #
 # #       # #
 # #   #   # #
 # ######### #
 #           #
 #############


      #####
      #   ##
      # $  #
######## #@##
# .  # $ $  #
#        $# #
#...#####   #
#####   #####


 ###########
##.......  #
# $$$$$$$@ #
#   # # # ##
# # #     #
#   #######
#####


## ####
####  ####
 # $ $.  #
## #  .$ #
#   ##.###
#  $  . #
# @ #   #
#  ######
####


  #########
###   #   #
# * $ . . #
#   $ ## ##
####*#   #
 #  @  ###
 #   ###
 #####


  #########
### @ #   #
# * $ *.. #
#   $ #   #
####*#  ###
 #     ##
 #   ###
 #####


#####  #####
#   ####.. #
# $$$      #
#   $#  .. #
### @#  ## #
  #  ##    #
  ##########


#####
#   #
# . #
#.@.###
##.#  #
#  $  #
# $   #
##$$  #
 #  ###
 #  #
 ####


####
# @###
#.*  #####
#..#$$ $ #
##       #
 # # ##  #
 #   #####
 #####


 #######
 #  . .###
 # . . . #
### #### #
#  @$  $ #
#  $$  $ #
####   ###
   #####


        ####
#########  #
#   ## $   #
#  $   ##  #
### #. .# ##
  # #. .#$##
  # #   #  #
  # @ $    #
  #  #######
  ####


#######
#     #####
# $$#@##..#
# #       #
#  $ # #  #
#### $  ..#
   ########


 #######
 #     #
## ###$##
#.$   @ #
# .. #$ #
#.##  $ #
#    ####
######


       ####
      ##  ###
####  #  $  #
#  #### $ $ #
#   ..# #$  #
#  #   @  ###
## #..# ###
 # ## # #
 #      #
 ########


  ####
###  #
#    ###
# # . .#
# @ ...####
# # # #   ##
#   # $$   #
#####  $ $ #
    ##$ # ##
     #    #
     ######


 ####
##  ####
#   ...#
#   ...#
#   # ##
#   #@ #### ####
##### $   ###  #
    #  ##$ $   #
   ###     $$  #
   # $  ##   ###
   #    ######
   ######


######## #####
#  #   ###   #
#      ## $  #
#.# @ ## $  ##
#.#   # $  ##
#.#    $  ##
#. ## #####
##    #
 ######


  ########
  #  # . #
  #   .*.#
  #  # * #
####$##.##
#      $ #
# $ ## $ #
#   @#   #
##########


  ####
  #  #
  #  ####
###$.$  #
#  .@.  #
#  $.$###
####  #
   #  #
   ####


####
#  ####
# $   #
# .#  #
# $# ##
# .  #
#### #
   # #
 ### ###
 #  $  #
## #$# ##
# $ @ $ #
# ..#.. #
###   ###
  #####


   ####
 ###  #####
 # $$ #   #
 # $ . .$$##
 # .. #. $ #
### #** .  #
#  . **# ###
# $ .# .. #
##$$.@. $ #
 #   # $$ #
 #####  ###
     ####


   #####
   # @ #
  ##   ##
###.$$$.###
#  $...$  #
#  $.#.$  #
#  $...$  #
###.$$$.###
  ##   ##
   #   #
   #####


 #######
##  .  ##
# .$$$. #
# $. .$ #
#.$ @ $.#
# $. .$ #
# .$$$. #
##  .  ##
 #######


       #####
########   #
#.   .  @#.#
#  ###     #
## $  #    #
 # $   #####
 # $#  #
 ## #  #
  #   ##
  #####


###########
#  .  #   #
# #.  @   #
#  #..# #######
##  ## $$ $ $ #
 ##           #
  #############


 ####
##  ###
#@$   #
### $ #
 #  ######
 #  $....#
 #  # ####
 ## # #
 # $# #
 #    #
 #  ###
 ####


     ####
 #####  #
 #     $#######
## ## ..#  ...#
# $ $$#$  @   #
#        ###  #
#######  # ####
      ####


   ####
   #  #
 ###  #
##  $ #
#   # #
# #$$ ######
# #   #   .#
#  $  @   .#
###  ####..#
  ####  ####


###### ####
#     #    #
#.##  #$##  #
#   #     #  #
#$  # ###  #  #
# #      #  # #
# # ####  # # #
#. @    $ * . #
###############


#############
#.# @#  #   #
#.#$$   # $ #
#.#  # $#   #
#.# $#  # $##
#.#  # $#  #
#.# $#  # $#
#..  # $   #
#..  #  #  #
############


 ############################
 #                          #
 # ######################## #
 # #                      # #
 # # #################### # #
 # # #                  # # #
 # # # ################ # # #
 # # # #              # # # #
 # # # # ############ # # # #
 # # # # #            # # # #
 # # # # # ############ # # #
 # # # # #              # # #
 # # # # ################ # #
 # # # #                  # #
##$# # #################### #
#. @ #                      #
#############################


    ######               ####
#####*#  #################  ##
#   ###                      #
#        ########  ####  ##  #
### ####     #  ####  ####  ##
#*# # .# # # #     #     #   #
#*# #  #     # ##  # ##  ##  #
###    ### ###  # ##  # ##  ##
 #   # #*#      #     # #    #
 #   # ###  #####  #### #    #
 #####   #####  ####### ######
 #   # # #**#               #
## # #   #**#  #######  ##  #
#    #########  #    ##### ###
# #             # $        #*#
#   #########  ### @#####  #*#
#####       #### ####   ######
)"
);

