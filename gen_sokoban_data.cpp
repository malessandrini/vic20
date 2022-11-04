#include <cstdint>
#include <string>
#include <vector>
#include <iostream>
#include <cassert>
#include <algorithm>
#include <sstream>

extern const std::string microban;


struct Level {
	Level(const std::vector<std::string>&);
	std::vector<uint8_t> cells;
	unsigned rows, columns;
	static std::vector<Level> read_data(const std::string &);  // throws
	static constexpr uint8_t wall = 1, goal = 2, stone = 4, man = 8;
	unsigned num_stones() const;
};


int main() {
	auto levels = Level::read_data(microban);
	std::cout << "Levels: " << levels.size() << std::endl;
	for (int i = 0; i < levels.size(); ++i)
		std::cout << i + 1 << " " << levels[i].rows << "x" << levels[i].columns << " " << (levels[i].rows * levels[i].columns) << "\n";
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

