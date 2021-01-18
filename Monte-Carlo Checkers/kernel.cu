// includes, system
#include <stdio.h>
#include <iostream>
#include <iomanip>
#include <string>
#include <random>
#include <chrono>
#include <algorithm>

// includes, cuda
#include "cuda_runtime.h"
#include "device_launch_parameters.h"

////////////////////////////////////////////////////////////////////////////////
#define BG_BBLUE_FG_BLACK "\033[3;104;30m"
#define BG_BLUE_FG_BLACK "\033[3;44;30m"
#define BG_BLUE_FG_WHITE "\033[3;44;37m"
#define BG_BLACK_FG_WHITE "\033[0m"

// 0 - 0000 = empty
// 4 - 0100 = black man
// 5 - 0101 = black king
// 6 - 0110 = white man
// 7 - 0111 = white king
//
// 8 - 1000 = out of bounds

////////////////////////////////////////////////////////////////////////////////
void init_board(unsigned int board[4]);
void draw_board(unsigned int board[4]);
inline unsigned int get_val(unsigned int& idx, unsigned int board[4]);
inline bool is_empty(unsigned int& tile);
inline bool is_piece(unsigned int& tile);
inline bool is_white(unsigned int& tile);
inline bool is_black(unsigned int& tile);
inline bool is_king (unsigned int& tile);
unsigned int get_left_upper_idx(unsigned int& cur_tile_idx, unsigned int board[4]);
unsigned int get_right_upper_idx(unsigned int& cur_tile_idx, unsigned int board[4]);
unsigned int get_left_lower_idx(unsigned int& cur_tile_idx, unsigned int board[4]);
unsigned int get_right_lower_idx(unsigned int& cur_tile_idx, unsigned int board[4]);
inline bool get_beating_pos(unsigned int& move_pos);
inline void set_beating_pos(unsigned int& move_pos);
inline bool get_move_check_guard(unsigned int& move_pos);
inline void set_move_check_guard(unsigned int& move_pos);
inline void clear_move_check_guard(unsigned int& move_pos);
inline unsigned int get_num_of_moves(unsigned int& move_pos);
inline void set_num_of_moves(unsigned int& move_pos, unsigned int& num_of_moves);
void get_move_possibility_loop_fun(unsigned int board[4], unsigned int move_pos[3], unsigned int& cur_idx, unsigned int& moves_idx, bool& whites_turn);
void get_move_possibility(unsigned int board[4], unsigned int move_pos[3], bool whites_turn);
////////////////////////////////////////////////////////////////////////////////
unsigned int translate_cords_to_idx(const char cords[2]);
////////////////////////////////////////////////////////////////////////////////
void test_get_idx_funs(unsigned int board[4]);
void test_get_move_possibility(unsigned int board[4], unsigned int move_possibility[3], bool whites_turn);
void test_get_move_possibility_board_init(unsigned int board[4], unsigned int test_choice);
void test_get_move_possibility_init_loop(unsigned int board[4], int lower_bound = 1, int upper_bound = 7);
void test_translate_cords_to_idx();
void test_translate_idx_to_cords();
void bench(unsigned int board[4]);
////////////////////////////////////////////////////////////////////////////////
void init_board(unsigned int board[4])
{
    // white bottom
    board[0] = 1145324612; //1st 2nd rows
    board[1] = 17476; //3rd 4th rows
    board[2] = 1717960704; //5th 6th rows
    board[3] = 1717986918; //7th 8th rows
}

void draw_board(unsigned int board[4])
{
    unsigned short i = 0, left_side_idx = 1;
    bool white_first = true;

    std::cout << BG_BBLUE_FG_BLACK << "   ";
    for (char c = 'A'; c != 'I'; ++c)
        std::cout << ' ' << c << ' ';
    std::cout << BG_BLACK_FG_WHITE << std::endl;

    for (; i < 4; ++i) // i = board_idx
    {
        for (unsigned int j = 0; j < 8; ++j) // j = tile_in_board_idx
        {
            unsigned int tile = board[i] << (28 - (j << 2)) >> 28;
            
            if (j == 0 || j == 4) std::cout << BG_BBLUE_FG_BLACK << ' ' << left_side_idx++ << ' ';

            if (white_first) std::cout << BG_BBLUE_FG_BLACK << "   ";

            if (is_piece(tile))
            {
                if (is_white(tile)) std::cout << BG_BLUE_FG_WHITE;
                else std::cout << BG_BLUE_FG_BLACK;
                if (is_king(tile)) std::cout << " K ";
                else std::cout << " @ ";
            }
            else std::cout << BG_BLUE_FG_BLACK << "   ";
            
            if (!white_first) std::cout << BG_BBLUE_FG_BLACK << "   ";

            if ((j & 3) == 3) // swap colors for second row
            {
                std::cout << BG_BLACK_FG_WHITE << std::endl;
                white_first = !white_first;
            }
        }
    }
    std::cout << BG_BLACK_FG_WHITE << std::endl;
}

inline unsigned int get_val(unsigned int& idx, unsigned int board[4]) 
{
    return idx > 31 ? 8 : board[idx >> 3] << 28 - ((idx & 7) << 2) >> 28;
}

////////////////////////////////////////////////////////////////////////////////

inline bool is_empty(unsigned int& tile)
{
    return !tile;
}

inline bool is_piece(unsigned int& tile)
{
    return tile & 4;
}

inline bool is_white(unsigned int& tile)
{
    return tile & 2;
}

inline bool is_black(unsigned int& tile)
{
    return ~tile & 2;
}

inline bool is_king(unsigned int& tile)
{
    return tile & 1;
}

////////////////////////////////////////////////////////////////////////////////

unsigned int get_left_upper_idx(unsigned int& cur_tile_idx, unsigned int board[4])
{
    if (cur_tile_idx > 31 || !(cur_tile_idx >> 2)) return 32; // second condition is top row
    if (cur_tile_idx & 4) // even row (counting from 1)
    {
        if (cur_tile_idx & 3) // if not left-most
            return cur_tile_idx - 5;
        return 32;
    }
    else // odd row
    {
        return cur_tile_idx - 4;
    }
}

unsigned int get_right_upper_idx(unsigned int& cur_tile_idx, unsigned int board[4])
{
    if (cur_tile_idx > 31 || !(cur_tile_idx >> 2)) return 32; // second cond chcks if top row
    if (cur_tile_idx & 4) // even row (counting from 1)
    {
        return cur_tile_idx - 4;
    }
    else // odd row
    {
        if (~cur_tile_idx & 3) // if not right-most
            return cur_tile_idx - 3;
        return 32;
    }
}

unsigned int get_left_lower_idx(unsigned int& cur_tile_idx, unsigned int board[4])
{
    if (cur_tile_idx > 31 || (cur_tile_idx >> 2) == 7) return 32; // second cond chcks if bottom row
    if (cur_tile_idx & 4) // even row (counting from 1)
    {
        if (cur_tile_idx & 3) // if not left-most
            return cur_tile_idx + 3;
        return 32;
    }
    else // odd row
    {
        return cur_tile_idx + 4;
    }
}

unsigned int get_right_lower_idx(unsigned int& cur_tile_idx, unsigned int board[4])
{
    if(cur_tile_idx > 31 || (cur_tile_idx >> 2) == 7) return 32; // second cond chcks if bottom row
    if (cur_tile_idx & 4) // even row (counting from 1)
    {
        return cur_tile_idx + 4;
    }
    else // odd row
    {
        if (~cur_tile_idx & 3) // if not right-most
            return cur_tile_idx + 5;
        return 32;
    }
}

inline bool get_beating_pos(unsigned int& move_pos)
{
    return (move_pos >> 16) & 1;
}

inline void set_beating_pos(unsigned int& move_pos)
{
    move_pos |= 1 << 16;
}

inline bool get_move_check_guard(unsigned int& move_pos)
{
    return (move_pos >> 17) & 1;
}

inline void set_move_check_guard(unsigned int& move_pos)
{
    move_pos |= 1 << 17;
}

inline void clear_move_check_guard(unsigned int& move_pos)
{
    move_pos &= 4294836223;
}

inline unsigned int get_num_of_moves(unsigned int& move_pos)
{
    return move_pos >> 20;
}

inline void set_num_of_moves(unsigned int& move_pos, unsigned int& num_of_moves)
{
    move_pos |= num_of_moves << 20;
}

void get_move_possibility_loop_fun(unsigned int board[4], unsigned int move_pos[3], unsigned int& cur_idx, unsigned int& moves_idx, bool& whites_turn)
{
    unsigned int tile, tmp_idx, result;
    tile = get_val(cur_idx, board);
    if (is_piece(tile) && (whites_turn == is_white(tile)))
    {
        unsigned int (*get_dir_idx_ptr)(unsigned int&, unsigned int*);
        for (unsigned int direction = 0; direction < 4; ++direction)
        {
            if (whites_turn == (bool)(direction & 2) && !is_king(tile)) // do not check backwards movement
                continue;
            switch (direction)
            {
            case 0:
                get_dir_idx_ptr = &get_left_upper_idx;
                break;
            case 1:
                get_dir_idx_ptr = &get_right_upper_idx;
                break;
            case 2:
                get_dir_idx_ptr = &get_left_lower_idx;
                break;
            case 3:
                get_dir_idx_ptr = &get_right_lower_idx;
                break;
            default: return;
            }
            tmp_idx = get_dir_idx_ptr(cur_idx, board);
            result = get_val(tmp_idx, board);
            if (whites_turn != is_white(result) && is_piece(result)) // is_piece = out of bounds guard
            {
                tmp_idx = get_dir_idx_ptr(tmp_idx, board);
                result = get_val(tmp_idx, board);
                if (is_empty(result))
                {
                    if (!get_beating_pos(move_pos[2])) 
                    {
                        moves_idx = 0;
                        move_pos[0] = move_pos[1] = move_pos[2] = 0;
                        set_beating_pos(move_pos[2]);
                    }
                    move_pos[moves_idx >> 2] |= cur_idx << ((moves_idx & 3) << 3);
                    ++moves_idx;
                    clear_move_check_guard(move_pos[2]);
                    return;
                }
            }
            else if (is_empty(result) && !get_beating_pos(move_pos[2]) && !get_move_check_guard(move_pos[2]))
            {
                move_pos[moves_idx >> 2] |= cur_idx << ((moves_idx & 3) << 3);
                ++moves_idx;
                set_move_check_guard(move_pos[2]);
                continue;
            }
        }
        clear_move_check_guard(move_pos[2]);
    }
}

// Index of tile that can be moved is stored similarly as board representation, but in 8 bits instead of 4 bits
// Additionally some space in move_pos[2] is used for flags and saving number of indexes in the whole array
void get_move_possibility(unsigned int board[4], unsigned int move_pos[3], bool whites_turn)
{
    move_pos[0] = move_pos[1] = move_pos[2] = 0;
    unsigned int moves_idx = 0;
    for (unsigned int i = 0; i < 32; ++i)
        get_move_possibility_loop_fun(board, move_pos, i, moves_idx, whites_turn);
    set_num_of_moves(move_pos[2], moves_idx); // record number of possible moves
}

////////////////////////////////////////////////////////////////////////////////

unsigned int translate_cords_to_idx(const char cords[2])
{
    if (cords[1] < '0' || cords[1] > '8') return 32; // out of bounds
    unsigned int cord1 = cords[1] - '1'; // not '0' because we count cords from 1
    switch (cords[0])
    {
    case 'A':
        if (~cord1 & 1) return 32;
        return cord1 << 2;
    case 'B':
        if (cord1 & 1) return 32;
        return cord1 << 2;
    case 'C':
        if (~cord1 & 1) return 32;
        return (cord1 << 2) + 1;
    case 'D':
        if (cord1 & 1) return 32;
        return (cord1 << 2) + 1;
    case 'E':
        if (~cord1 & 1) return 32;
        return (cord1 << 2) + 2;
    case 'F':
        if (cord1 & 1) return 32;
        return (cord1 << 2) + 2;
    case 'G':
        if (~cord1 & 1) return 32;
        return (cord1 << 2) + 3;
    case 'H':
        if (cord1 & 1) return 32;
        return (cord1 << 2) + 3;
    default:
        return 32;
    }
}

void translate_idx_to_cords(unsigned int idx, char cords[2])
{
    if (idx > 31) {
        cords[0] = '-';
        cords[1] = '-';
        return;
    }
    else if (idx < 4) cords[1] = '1';
    else if (idx >= 4 && idx < 8) cords[1] = '2';
    else if (idx >= 8 && idx < 12) cords[1] = '3';
    else if (idx >= 12 && idx < 16) cords[1] = '4';
    else if (idx >= 16 && idx < 20) cords[1] = '5';
    else if (idx >= 20 && idx < 24) cords[1] = '6';
    else if (idx >= 24 && idx < 28) cords[1] = '7';
    else if (idx >= 28 && idx < 32) cords[1] = '8';
    if ((idx & 7) == 0) cords[0] = 'B';
    else if ((idx & 7) == 1) cords[0] = 'D';
    else if ((idx & 7) == 2) cords[0] = 'F';
    else if ((idx & 7) == 3) cords[0] = 'H';
    else if ((idx & 7) == 4) cords[0] = 'A';
    else if ((idx & 7) == 5) cords[0] = 'C';
    else if ((idx & 7) == 6) cords[0] = 'E';
    else if ((idx & 7) == 7) cords[0] = 'G';
}

////////////////////////////////////////////////////////////////////////////////

int main(int argc, char** argv)
{
    unsigned int board[4];

    init_board(board);
    draw_board(board);

    unsigned int move_possibility[3]{};

    bool whites_turn = true;
    test_get_move_possibility(board, move_possibility, whites_turn);

    whites_turn = false;
    test_get_move_possibility(board, move_possibility, whites_turn);
    std::cout << std::endl;

    std::cout << std::endl;
    //test_get_idx_funs(board);
    //std::cout << std::endl;
    test_translate_cords_to_idx();
    test_translate_idx_to_cords();
    std::cout << std::endl;
    //test_get_move_possibility_init_loop(board);

    //bench(board);

    return 0;
}

////////////////////////////////////////////////////////////////////////////////
void test_get_idx_funs(unsigned int board[4])
{
    //test top
    unsigned int tmp = 0;
    std::cout << (32 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (4 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (5 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 1;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (5 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (6 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 3;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (7 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    // test even
    tmp = 4;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (0 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (8 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 5;
    std::cout << std::endl << (0 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (1 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (8 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (9 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 7;
    std::cout << std::endl << (2 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (3 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (10 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (11 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    //test odd
    tmp = 8;
    std::cout << std::endl << (4 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (5 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (12 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (13 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 9;
    std::cout << std::endl << (5 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (6 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (13 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (14 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 11;
    std::cout << std::endl << (7 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (15 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    //test bottom
    tmp = 28;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (24 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 29;
    std::cout << std::endl << (24 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (25 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;

    tmp = 31;
    std::cout << std::endl << (26 == get_left_upper_idx(tmp, board)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp, board);
    std::cout << std::endl << (27 == get_right_upper_idx(tmp, board)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp, board);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp, board)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp, board);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp, board)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp, board);
    std::cout << std::endl;
}

void test_get_move_possibility(unsigned int board[4], unsigned int move_possibility[3], bool whites_turn)
{
    get_move_possibility(board, move_possibility, whites_turn);
    std::cout << std::endl << "Possible moves " << (whites_turn ? "for white: " : "for black: ") << get_num_of_moves(move_possibility[2]) << std::endl;
    std::cout << "Indices of pawns possible to move: ";
    for (unsigned int i = 0; i < get_num_of_moves(move_possibility[2]); ++i)
    {
        std::cout << (move_possibility[i >> 2] << 24 - ((i & 3) << 3) >> 24) << ' ';
    }
    std::cout << std::endl;
}

void test_get_move_possibility_board_init(unsigned int board[4], unsigned int test_choice)
{
    init_board(board);
    switch (test_choice)
    {
    case 0:
        // black bottom - outdated
        board[0] = 1717986918; //1st 2nd rows
        board[1] = 26214; //3rd 4th rows
        board[2] = 1145307136; //5th 6th rows
        board[3] = 1145324612; //7th 8th rows
        break;
    case 1:
        // test 1 - white forward beating
        // expected - white = 2 moves, idx : 22 23
        // expected - black = 4 moves, idx : 8 9 10 11
        board[2] = 1717986304; //5th 6th rows
        break;
    case 2:
        // test 2 - white no backward beating, black forward beating
        // expected - white = 2 moves, idx: 19 23
        // expected - black = 2 moves, idx: 5 18
        board[1] = 1078198368;
        board[2] = 1717986304;
        board[3] = 1717986822;
        break;
    case 3:
        // test 3 - black no backward beating
        // expected - white = 5 moves, idx: 9 20 21 22 23
        // expected - black = 1 move,  idx: 5
        board[0] = 1078215748;
        board[1] = 1078198368;
        break;
    case 4:
        // test 4
        // expected - white = 5 moves, idx: 9 20 21 22 23
        // expected - black = 8 moves, idx: 0 1 4 6 7 12 13 15
        board[0] = 1141130308;
        board[1] = 1078198368;
        break;
    case 5:
        // test 5 - black King backward beating
        // expected - white = 5 moves, idx: 9 20 21 22 23
        // expected - black = 1 move,  idx: 5 13
        board[0] = 1078215748;
        board[1] = 1079246944;
        break;
    case 6:
        // test 6 - white King backward beating
        // expected - white = 1 move,  idx: 9
        // expected - black = 8 moves, idx: 0 1 4 6 7 12 13 15
        board[0] = 1141130308;
        board[1] = 1078198384;
        break;
    default:
        break;
    }
}

void test_get_move_possibility_init_loop(unsigned int board[4], int lower_bound, int upper_bound)
{
    for (int i = lower_bound; i < upper_bound; ++i)
    {
        system("pause");
        test_get_move_possibility_board_init(board, i);
        system("CLS");
        draw_board(board);

        std::cout << "Running test " << i << std::endl;

        unsigned int move_possibility[3]{};
        bool whites_turn = true;
        test_get_move_possibility(board, move_possibility, whites_turn);

        whites_turn = false;
        test_get_move_possibility(board, move_possibility, whites_turn);
        std::cout << std::endl;

        std::cout << std::endl;
        //test_get_idx_funs(board);
        //std::cout << std::endl;
        test_translate_cords_to_idx();
        std::cout << std::endl;
    }
}

void test_translate_cords_to_idx()
{
    char cords[2] = {'A', '1'};
    for (char c2 = '1'; c2 < '9'; ++c2)
    {
        cords[1] = c2;
        for (char c1 = 'A'; c1 < 'I'; ++c1)
        {
            cords[0] = c1;
            unsigned int idx = translate_cords_to_idx(cords);
            std::cout << cords[0] << cords[1] << ": " << (32 == idx ? "--" : std::to_string(idx)) << '\t';
        }
        std::cout << std::endl;
    }
    std::cout << std::endl;
}

void test_translate_idx_to_cords()
{
    char cords[2] = { '-', '-' };
    std::cout << '\t';
    for (unsigned int idx = 0; idx < 32; ++idx)
    {
        translate_idx_to_cords(idx, cords);
        std::cout << (idx > 9 ? '\0' : ' ') << idx << ": " << cords[0] << cords[1] << "\t\t";
        if ((idx & 3) == 3) std::cout << std::endl;
        if ((idx & 7) == 7) std::cout << '\t';
    }
    std::cout << std::endl;
}

void bench(unsigned int board[4])
{
    std::chrono::steady_clock::time_point start, finish, start2, finish2;
    std::chrono::duration<double> elapsed, elapsed2;

    start = std::chrono::high_resolution_clock::now();
    for (unsigned int i = 0; i < 1000000; ++i)
    {
        for (unsigned int idx = 0; idx < 32; ++idx)
        {
            //get_val(idx, board);
            int tmp = get_val(idx, board) & 3;
            //int tmp = get_val(idx, board) << 2;
            //int tmp = get_val(idx, board) >> 2;
            //int tmp = get_val(idx, board);
            //int tmp = 16 | 123;
        }
    }
    finish = std::chrono::high_resolution_clock::now();
    elapsed = (finish - start) / 1000000;

    start2 = std::chrono::high_resolution_clock::now();
    for (unsigned int i = 0; i < 1000000; ++i)
    {
        for (unsigned int idx = 0; idx < 32; ++idx)
        {
            //get_val2(idx, board);
            int tmp = get_val(idx, board) % 4;
            //int tmp = get_val(idx, board) * 4;
            //int tmp = get_val(idx, board) / 4;
            //int tmp = get_val(idx, board) / 4;
            //int tmp = 16 ^ 123;
        }
    }
    finish2 = std::chrono::high_resolution_clock::now();
    elapsed2 = (finish2 - start2) / 1000000;

    //std::cout << "Average time for get_val:  " << elapsed.count() << std::endl;
    //std::cout << "Average time for get_val2: " << elapsed2.count() << std::endl << std::endl;
    std::cout << "Average time for & 3:\t" << elapsed.count() << std::endl;
    std::cout << "Average time for % 4:\t" << elapsed2.count() << std::endl << std::endl;
    //std::cout << "Average time for << 2:\t" << elapsed.count() << std::endl;
    //std::cout << "Average time for * 4:\t" << elapsed2.count() << std::endl << std::endl;
    //std::cout << "Average time for >> 2:\t" << elapsed.count() << std::endl;
    //std::cout << "Average time for / 4:\t" << elapsed2.count() << std::endl << std::endl;
    //std::cout << "Average time for get:\t" << elapsed.count() << std::endl;
    //std::cout << "Average time for get/4:\t" << elapsed2.count() << std::endl << std::endl;
    //std::cout << "Average time for | :\t" << elapsed.count() << std::endl;
    //std::cout << "Average time for ^ :\t" << elapsed2.count() << std::endl << std::endl;
}