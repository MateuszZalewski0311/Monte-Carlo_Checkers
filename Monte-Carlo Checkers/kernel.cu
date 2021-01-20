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
#define BG_BBLUE_FG_BLACK "\033[104;30m"
#define BG_BLUE_FG_BLACK "\033[44;30m"
#define BG_BLUE_FG_WHITE "\033[44;37m"
#define BG_BLACK_FG_WHITE "\033[0m"
#define BG_WHITE_FG_BLACK "\033[30;107m"

// 0 - 0000 = empty
// 4 - 0100 = black man
// 5 - 0101 = black king
// 6 - 0110 = white man
// 7 - 0111 = white king
//
// 8 - 1000 in (tile_idx = 0) is used to save turn flag (1 - white, 0 - black)
//
// 8 tiles saved in one unsigned int with encoding as above
// example: 0100 0100 0100 0100 0000 0000 0000 0000
// indexing: 7 6 5 4 3 2 1 0

//////////////////////////////////////////////////////////////////////////////// - board state macros
#define SET_VAL_BOARD(idx, val, board) board[idx >> 3] ^= (board[idx >> 3] ^ val << ((idx & 7) << 2)) & (15 << ((idx & 7) << 2))
#define GET_VAL_BOARD(idx, board) board[idx >> 3] << 28 - ((idx & 7) << 2) >> 28
#define GET_VAL_BOARD_S(idx, board) idx > 31 ? 8 : board[idx >> 3] << 28 - ((idx & 7) << 2) >> 28
//#define IS_EMPTY(tile) (bool)(!tile)
#define IS_PIECE(tile) (bool)(tile & 4)
#define IS_WHITE(tile) (bool)(tile & 2)
#define IS_BLACK(tile) (bool)(~tile & 2)
#define IS_KING(tile) (bool)(tile & 1)
#define FLIP_TURN_FLAG(board) board[0] ^= 8
#define GET_TURN_FLAG(board) (bool)(board[0] & 8)
//////////////////////////////////////////////////////////////////////////////// - move_pos array macros
#define GET_BEATING_POS_FLAG(move_pos) (bool)(move_pos[3] & 1)
#define SET_BEATING_POS_FLAG(move_pos) move_pos[3] |= 1
#define GET_MOVE_CHECK_GUARD(move_pos) (bool)(move_pos[3] & 2)
#define SET_MOVE_CHECK_GUARD(move_pos) move_pos[3] |= 2
#define CLEAR_MOVE_CHECK_GUARD(move_pos) move_pos[3] &= ~2
#define GET_NUM_OF_MOVES(move_pos) move_pos[3] >> 2
#define SET_NUM_OF_MOVES(move_pos, num_of_moves) move_pos[3] |= num_of_moves << 2
#define GET_VAL_MOVE_POS(idx, move_pos) move_pos[idx >> 2] << 24 - ((idx & 3) << 3) >> 24
#define SET_VAL_MOVE_POS(idx, val, move_pos) move_pos[idx >> 2] |= val << ((idx & 3) << 3)
#define GET_PIECE_DIR_FLAG(dir, move_pos) (bool)((move_pos[2] << 30 - (dir << 1) >> 30) & 1)
#define SET_PIECE_DIR_FLAG(dir, move_pos) move_pos[2] |= 1 << (dir << 1)
#define GET_PIECE_BEATING_FLAG(dir, move_pos) (bool)((move_pos[2] << 30 - (dir << 1) >> 30) & 2)
#define SET_PIECE_BEATING_FLAG(dir, move_pos) move_pos[2] |= 2 << (dir << 1)
////////////////////////////////////////////////////////////////////////////////
void init_board(unsigned int board[4]);
void draw_board(unsigned int board[4]);
unsigned int get_left_upper_idx(unsigned int& cur_tile_idx);
unsigned int get_right_upper_idx(unsigned int& cur_tile_idx);
unsigned int get_left_lower_idx(unsigned int& cur_tile_idx);
unsigned int get_right_lower_idx(unsigned int& cur_tile_idx);
void get_move_possibility_loop_fun(unsigned int board[4], unsigned int move_pos[4], unsigned int& cur_idx, unsigned int& moves_idx);
void get_move_possibility(unsigned int board[4], unsigned int move_pos[4]);
////////////////////////////////////////////////////////////////////////////////
void get_piece_move_pos(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx);
void move_piece(unsigned int board[4], unsigned int& cur_tile_idx, unsigned int (*get_dir_idx_ptr)(unsigned int&));
////////////////////////////////////////////////////////////////////////////////
void game_loop(unsigned int board[4], void (*white_player)(unsigned int*, unsigned int*), void (*black_player)(unsigned int*, unsigned int*));
void human_player(unsigned int board[4], unsigned int move_pos[4]);
void random_player(unsigned int board[4], unsigned int move_pos[4]);
unsigned int simulate_game(unsigned int board[4]);
unsigned int count_beating_sequences_for_piece(unsigned int board[4], unsigned int cur_tile_idx, unsigned int dir);
void MTS_CPU_player(unsigned int board[4]);
////////////////////////////////////////////////////////////////////////////////
void disp_moveable_pieces(unsigned int board[4], unsigned int move_pos[4]);
void disp_possible_dirs(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx);
void get_cords_from_console(char cords[2]);
unsigned int translate_cords_to_idx(const char cords[2]);
void translate_idx_to_cords(unsigned int idx, char cords[2]);
void get_end_state(unsigned int board[4]);
void disp_end_state(unsigned int* board);
////////////////////////////////////////////////////////////////////////////////
void testing_function();
void test_get_idx_funs(unsigned int board[4]);
void test_get_move_possibility(unsigned int board[4], unsigned int move_pos[4]);
void test_get_move_possibility_board_init(unsigned int board[4], unsigned int test_choice);
void test_get_move_possibility_init_loop(unsigned int board[4], int lower_bound = 1, int upper_bound = 7);
void test_get_piece_move_pos(unsigned int board[4], unsigned int move_pos[4], unsigned int idx);
void test_translate_cords_to_idx();
void test_translate_idx_to_cords();
//void bench(unsigned int board[4]);
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

            if (IS_PIECE(tile))
            {
                if (IS_WHITE(tile)) std::cout << BG_BLUE_FG_WHITE;
                else std::cout << BG_BLUE_FG_BLACK;
                if (IS_KING(tile)) std::cout << " K ";
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
}

////////////////////////////////////////////////////////////////////////////////

unsigned int get_left_upper_idx(unsigned int& cur_tile_idx)
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

unsigned int get_right_upper_idx(unsigned int& cur_tile_idx)
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

unsigned int get_left_lower_idx(unsigned int& cur_tile_idx)
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

unsigned int get_right_lower_idx(unsigned int& cur_tile_idx)
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

void get_move_possibility_loop_fun(unsigned int board[4], unsigned int move_pos[4], unsigned int& cur_idx, unsigned int& moves_idx)
{
    unsigned int tile, tmp_idx, result;
    tile = GET_VAL_BOARD(cur_idx, board);
    if (IS_PIECE(tile) && (GET_TURN_FLAG(board) == IS_WHITE(tile)))
    {
        unsigned int (*get_dir_idx_ptr)(unsigned int&);
        for (unsigned int direction = 0; direction < 4; ++direction)
        {
            if (GET_TURN_FLAG(board) == (bool)(direction & 2) && !IS_KING(tile)) // do not check backwards movement
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
            tmp_idx = get_dir_idx_ptr(cur_idx);
            if (tmp_idx == 32) continue;
            result = GET_VAL_BOARD(tmp_idx, board);
            if (GET_TURN_FLAG(board) != IS_WHITE(result) && IS_PIECE(result))
            {
                tmp_idx = get_dir_idx_ptr(tmp_idx);
                if (tmp_idx == 32) continue;
                result = GET_VAL_BOARD(tmp_idx, board);
                if (!IS_PIECE(result))
                {
                    if (!GET_BEATING_POS_FLAG(move_pos)) 
                    {
                        moves_idx = 0;
                        move_pos[0] = move_pos[1] = move_pos[2] = move_pos[3] = 0;
                        SET_BEATING_POS_FLAG(move_pos);
                    }
                    SET_VAL_MOVE_POS(moves_idx, cur_idx, move_pos);
                    ++moves_idx;
                    CLEAR_MOVE_CHECK_GUARD(move_pos);
                    return;
                }
            }
            else if (!IS_PIECE(result) && !GET_BEATING_POS_FLAG(move_pos) && !GET_MOVE_CHECK_GUARD(move_pos))
            {
                SET_VAL_MOVE_POS(moves_idx, cur_idx, move_pos);
                ++moves_idx;
                SET_MOVE_CHECK_GUARD(move_pos);
                continue;
            }
        }
        CLEAR_MOVE_CHECK_GUARD(move_pos);
    }
}

// Index of tile that can be moved is stored similarly as board representation, but in 8 bits instead of 4 bits
// Additionally some space in move_pos[2] is used for flags and saving number of indexes in the whole array
void get_move_possibility(unsigned int board[4], unsigned int move_pos[4])
{
    unsigned int moves_idx = 0;
    move_pos[0] = move_pos[1] = move_pos[2] = move_pos[3] = 0;
    for (unsigned int i = 0; i < 32; ++i)
        get_move_possibility_loop_fun(board, move_pos, i, moves_idx);
    SET_NUM_OF_MOVES(move_pos, moves_idx); // record number of possible moves
}

////////////////////////////////////////////////////////////////////////////////

// Index of tile that can be moved is stored similarly as board representation, but in 8 bits instead of 2 bits
// move_pos[2] is used for storing, the same spots as in get_move_possibility are used for beating available flag and number of indexes saved
void get_piece_move_pos(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx)
{
    unsigned int tile, tmp_idx, result, move_counter = 0;
    move_pos[2] = move_pos[3] = 0;
    
    tile = GET_VAL_BOARD_S(idx, board);
    if (IS_PIECE(tile))
    {
        unsigned int (*get_dir_idx_ptr)(unsigned int&);
        for (unsigned int direction = 0; direction < 4; ++direction)
        {
            if (IS_WHITE(tile) == (bool)(direction & 2) && !IS_KING(tile)) // do not check backwards movement
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
            tmp_idx = get_dir_idx_ptr(idx);
            if (tmp_idx == 32) continue;
            result = GET_VAL_BOARD(tmp_idx, board);
            if (IS_WHITE(tile) != IS_WHITE(result) && IS_PIECE(result)) // IS_PIECE = out of bounds guard
            {
                tmp_idx = get_dir_idx_ptr(tmp_idx);
                if (tmp_idx == 32) continue;
                result = GET_VAL_BOARD(tmp_idx, board);
                if (!IS_PIECE(result))
                {
                    if (!GET_BEATING_POS_FLAG(move_pos)) {
                        move_counter = 0;
                        SET_BEATING_POS_FLAG(move_pos);
                    }
                    SET_PIECE_BEATING_FLAG(direction, move_pos);
                    ++move_counter;
                }
            }
            else if (!IS_PIECE(result) && !GET_BEATING_POS_FLAG(move_pos))
            {
                SET_PIECE_DIR_FLAG(direction, move_pos);
                ++move_counter;
            }
        }
    }
    SET_NUM_OF_MOVES(move_pos, move_counter);
}

void move_piece(unsigned int board[4], unsigned int& cur_tile_idx, unsigned int (*get_dir_idx_ptr)(unsigned int&))
{
    if (cur_tile_idx > 31) return;
    
    unsigned int other_tile_idx = get_dir_idx_ptr(cur_tile_idx);
    if (other_tile_idx == 32) return;
    
    unsigned int cur_tile = GET_VAL_BOARD(cur_tile_idx, board);
    if (!(GET_VAL_BOARD(other_tile_idx, board)))
    {
        SET_VAL_BOARD(other_tile_idx, cur_tile, board);
        SET_VAL_BOARD(cur_tile_idx, 0, board);
    }
    else
    {
        SET_VAL_BOARD(other_tile_idx, 0, board);
        SET_VAL_BOARD(cur_tile_idx, 0, board);
        other_tile_idx = get_dir_idx_ptr(other_tile_idx);
        SET_VAL_BOARD(other_tile_idx, cur_tile, board);
    }
    if ((!IS_KING(cur_tile)) && ((IS_WHITE(cur_tile) && other_tile_idx < 4) || (IS_BLACK(cur_tile) && other_tile_idx > 27)))
        SET_VAL_BOARD(other_tile_idx, (cur_tile | 1), board); // promote to king
}

////////////////////////////////////////////////////////////////////////////////

void game_loop(unsigned int board[4], void (*white_player)(unsigned int*, unsigned int*), void (*black_player)(unsigned int*, unsigned int*))
{
    unsigned int move_pos[4];
    bool game_over = false;

    while (!game_over) // main loop
    {
        system("CLS");
        draw_board(board);
        std::cout << std::endl << (GET_TURN_FLAG(board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
        //get_move_possibility(board, move_pos);
        //system("pause");

        if (GET_TURN_FLAG(board))
            white_player(board, move_pos);
        else
            black_player(board, move_pos);

        get_move_possibility(board, move_pos);
        if (0 == (GET_NUM_OF_MOVES(move_pos))) game_over = true; // end game if noone can move
    }
}

void human_player(unsigned int board[4], unsigned int move_pos[4])
{
    unsigned int choosen_idx1, choosen_idx2, dir;
    char cords[2];
    bool board_beating_flag, beating_sequence_in_progress = false;

    auto redraw_beginning = [board]()
    {
        system("CLS");
        draw_board(board);
        std::cout << std::endl << (GET_TURN_FLAG(board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
    };
    auto redraw_first_stage = [board, move_pos, redraw_beginning]()
    {
        redraw_beginning();
        get_move_possibility(board, move_pos);
        disp_moveable_pieces(board, move_pos);
        std::cout << std::endl;
    };
    auto redraw_second_stage = [board, move_pos, &choosen_idx1, redraw_beginning]()
    {
        redraw_beginning();
        get_piece_move_pos(board, move_pos, choosen_idx1);
        disp_possible_dirs(board, move_pos, choosen_idx1);
        std::cout << std::endl;
    };

    human_player_reset:
    while (true) // piece choice loop
    {
        redraw_first_stage();
        get_cords_from_console(cords);
        choosen_idx1 = translate_cords_to_idx(cords);
        board_beating_flag = GET_BEATING_POS_FLAG(move_pos);

        get_piece_move_pos(board, move_pos, choosen_idx1);
        if (0 == (GET_NUM_OF_MOVES(move_pos)))
        {
            std::cout << std::endl << "This piece cannot move!" << std::endl << "Please choose a different piece!" << std::endl << std::endl;
            system("pause");
            continue;
        }
        else if (board_beating_flag != GET_BEATING_POS_FLAG(move_pos))
        {
            std::cout << std::endl << "BEATING POSSIBLE!" << std::endl << "Please choose a different piece!" << std::endl << std::endl;
            system("pause");
            continue;
        }
        break;
    }

    while (true) // move sequence loop
    {
        redraw_second_stage();
        get_cords_from_console(cords);
        choosen_idx2 = translate_cords_to_idx(cords);

        unsigned int (*get_dir_idx_ptr)(unsigned int&);
        for (dir = 0; dir < 4; ++dir)
        {
            if (dir < 2 && choosen_idx2 > choosen_idx1) continue;
            switch (dir)
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
            default: goto human_player_reset;
            }
            if (choosen_idx2 != get_dir_idx_ptr(choosen_idx1)) continue;

            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos))
            {
                board_beating_flag = IS_KING((GET_VAL_BOARD(choosen_idx1, board))); //memory recycling - dont mind the name
                move_piece(board, choosen_idx1, get_dir_idx_ptr);
                choosen_idx1 = get_dir_idx_ptr(choosen_idx2);
                if (board_beating_flag != (IS_KING((GET_VAL_BOARD(choosen_idx1, board)))))
                {
                    FLIP_TURN_FLAG(board);
                    return;
                }
                break;
            }
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_DIR_FLAG(dir, move_pos))
            {
                move_piece(board, choosen_idx1, get_dir_idx_ptr);
                FLIP_TURN_FLAG(board);
                return;
            }
            std::cout << std::endl << "Impossible move!" << std::endl << "Please choose a different move!" << std::endl << std::endl;
            system("pause");
            if (beating_sequence_in_progress) break;
            goto human_player_reset; // reset move choice
        }
        if (dir == 4)
        {
            std::cout << std::endl << "Impossible move!" << std::endl << "Please choose a different move!" << std::endl << std::endl;
            system("pause");
            if (beating_sequence_in_progress) continue;
            goto human_player_reset; // reset move choice
        }
        get_piece_move_pos(board, move_pos, choosen_idx1);
        if (!GET_BEATING_POS_FLAG(move_pos)) break; // check if more beatings in sequence
        beating_sequence_in_progress = true;
    }
    FLIP_TURN_FLAG(board);
}

void random_player(unsigned int board[4], unsigned int move_pos[4])
{
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<> dist(0, 0);
    unsigned int choosen_idx1, choosen_idx2, dir = 0, dir_idx_upper_bound, dir_idx_counter = 0;
    bool beating_sequence_in_progress = false, tmp;
    unsigned int (*get_dir_idx_ptr)(unsigned int&);

    get_move_possibility(board, move_pos);
    dir_idx_upper_bound = (GET_NUM_OF_MOVES(move_pos)) - 1;
    dist = std::uniform_int_distribution<>(0, dir_idx_upper_bound);
    choosen_idx1 = dist(gen);
    choosen_idx1 = GET_VAL_MOVE_POS(choosen_idx1, move_pos);
    do 
    {
        get_piece_move_pos(board, move_pos, choosen_idx1);
        dir_idx_upper_bound = (GET_NUM_OF_MOVES(move_pos)) - 1;
        dist = std::uniform_int_distribution<>(0, dir_idx_upper_bound);
        choosen_idx2 = dist(gen);
        for (dir = 0, dir_idx_counter = 0; dir_idx_counter <= dir_idx_upper_bound && dir < 4; ++dir)
        {
            switch (dir)
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
            if (dir_idx_counter == choosen_idx2);
            else if ((GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) || (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_DIR_FLAG(dir, move_pos)))
            {
                ++dir_idx_counter;
                continue;
            }
            else continue;
            
            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos))
            {
                tmp = IS_KING((GET_VAL_BOARD(choosen_idx1, board))); // for promotion check
                choosen_idx2 = get_dir_idx_ptr(choosen_idx1);
                move_piece(board, choosen_idx1, get_dir_idx_ptr);
                choosen_idx1 = get_dir_idx_ptr(choosen_idx2);
                if (tmp != (IS_KING((GET_VAL_BOARD(choosen_idx1, board)))))
                {
                    FLIP_TURN_FLAG(board);
                    return;
                }
                break;
            }
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_DIR_FLAG(dir, move_pos))
            {
                move_piece(board, choosen_idx1, get_dir_idx_ptr);
                FLIP_TURN_FLAG(board);
                return;
            }
        }
        if (dir == 4) return;
        get_piece_move_pos(board, move_pos, choosen_idx1);
        if (!GET_BEATING_POS_FLAG(move_pos)) break; // check if more beatings in sequence
        beating_sequence_in_progress = true;
    } while (beating_sequence_in_progress);
    FLIP_TURN_FLAG(board);
}

unsigned int simulate_game(unsigned int board[4])
{
    unsigned int move_pos[4];
    bool game_over = false;

    while (!game_over) // main loop
    {
        random_player(board, move_pos);
        get_move_possibility(board, move_pos);
        if (0 == (GET_NUM_OF_MOVES(move_pos))) game_over = true; // end game if noone can move
    }
    get_end_state(board);
    return board[0];
}

unsigned int count_beating_sequences_for_piece(unsigned int board[4], unsigned int cur_tile_idx, unsigned int dir)
{
    unsigned int piece_pos[4], tmp_board[4]{}, possible_moves = 0, dir_tile_idx;
    bool tmp;
    unsigned int (*get_dir_idx_ptr)(unsigned int&);
    
    tmp_board[0] = board[0]; tmp_board[1] = board[1]; tmp_board[2] = board[2]; tmp_board[3] = board[3];
    get_piece_move_pos(tmp_board, piece_pos, cur_tile_idx);
    switch (dir)
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
    default: system("CLS"); std::cout << "ERROR"; system("pause"); exit(EXIT_FAILURE);
    }
    if (GET_BEATING_POS_FLAG(piece_pos) && GET_PIECE_BEATING_FLAG(dir, piece_pos))
    {
        tmp = IS_KING((GET_VAL_BOARD(cur_tile_idx, tmp_board))); // for promotion check
        dir_tile_idx = get_dir_idx_ptr(cur_tile_idx);
        move_piece(tmp_board, cur_tile_idx, get_dir_idx_ptr);
        cur_tile_idx = get_dir_idx_ptr(dir_tile_idx);
        ++possible_moves;
        if (tmp != (IS_KING((GET_VAL_BOARD(cur_tile_idx, tmp_board)))))
        {
            return possible_moves;
        }
        get_piece_move_pos(tmp_board, piece_pos, cur_tile_idx);
        if (GET_BEATING_POS_FLAG(piece_pos)) // check if more beatings in sequence
        {
            possible_moves = 0;
            for (unsigned int dir = 0; dir < 4; ++dir)
                possible_moves += count_beating_sequences_for_piece(tmp_board, cur_tile_idx, dir);
        }
    }
    return possible_moves;
}

void MTS_CPU_player(unsigned int board[4])
{
    //std::random_device rd;
    //std::mt19937 gen(rd());
    //std::uniform_int_distribution<> dist(0, 0);
    unsigned int move_pos[4]{};// , piece_pos[4]{}, tmp_board[4]{}, possible_moves = 0, ** first_layer;
    unsigned int cur_tile_idx;
    //unsigned int (*get_dir_idx_ptr)(unsigned int&);

    get_move_possibility(board, move_pos);
    for (unsigned int i = 0; i < GET_NUM_OF_MOVES(move_pos); ++i)
    {
        cur_tile_idx = GET_VAL_MOVE_POS(i, move_pos);
        //possible_moves += count_beating_sequences_for_piece(board, cur_tile_idx);
    }
    //first_layer = new unsigned int *[GET_NUM_OF_MOVES(move_pos)];
    //for (unsigned int i = 0; i < GET_NUM_OF_MOVES(move_pos); ++i)
    //    first_layer[i] = new unsigned int[4];
    //(first_layer[move_idx] = board
}

////////////////////////////////////////////////////////////////////////////////

void disp_moveable_pieces(unsigned int board[4], unsigned int move_pos[4])
{
    char cords[2]{'-'};
    std::cout << "Possible moves for " << (GET_TURN_FLAG(board) ? "white" : "black") << " - " << (GET_NUM_OF_MOVES(move_pos)) << std::endl;
    std::cout << "Tiles with moveable pieces: ";
    for (unsigned int i = 0; i < GET_NUM_OF_MOVES(move_pos); ++i)
    {
        translate_idx_to_cords((GET_VAL_MOVE_POS(i, move_pos)), cords);
        std::cout << cords[0] << cords[1] << ' ';
    }
    std::cout << std::endl;
}

void disp_possible_dirs(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx)
{
    char cords[2]{'-'};
    translate_idx_to_cords(idx, cords);

    get_piece_move_pos(board, move_pos, idx);
    if (GET_NUM_OF_MOVES(move_pos))
    {
        std::cout << "Moves possible for piece on " << cords[0] << cords[1] << " - " << (GET_NUM_OF_MOVES(move_pos)) << std::endl;
        if (GET_BEATING_POS_FLAG(move_pos)) std::cout << "BEATING POSSIBLE!" << std::endl;
        std::cout << "List of tiles to choose from: ";
        unsigned int (*get_dir_idx_ptr)(unsigned int&);
        for (unsigned int dir = 0; dir < 4; ++dir)
        {
            switch (dir)
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
            default: break;
            }
            translate_idx_to_cords(get_dir_idx_ptr(idx), cords);
            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) std::cout << cords[0] << cords[1] << ' ';
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_DIR_FLAG(dir, move_pos)) std::cout << cords[0] << cords[1] << ' ';
        }
        std::cout << std::endl;
    }
    else std::cout << "Movement not possible for piece on " << cords[0] << cords[1] << std::endl;
}

void get_cords_from_console(char cords[2])
{
    while (true)
    {
        std::string input = "";
        std::cout << "Please provide coordinates: ";
        std::getline(std::cin, input);
        if (input.size() != 2)
        {
            std::cout << "Incorrect input length!" << std::endl << std::endl;
            continue;
        }
        cords[0] = toupper(input[0]);
        cords[1] = toupper(input[1]);
        if ((cords[0] == 'A' || cords[0] == 'C' || cords[0] == 'E' || cords[0] == 'G') && (cords[1] == '2' || cords[1] == '4' || cords[1] == '6' || cords[1] == '8')) break;
        else if ((cords[0] == 'B' || cords[0] == 'D' || cords[0] == 'F' || cords[0] == 'H') && (cords[1] == '1' || cords[1] == '3' || cords[1] == '5' || cords[1] == '7')) break;
        std::cout << "Incorrect coordinates given!" << std::endl << std::endl;
    }
}

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

// saves end state in board[0], 0 - error, 1 - black win, 2 - white win, 3 - draw 
void get_end_state(unsigned int board[4])
{
    unsigned int move_pos[4];
    
    get_move_possibility(board, move_pos);
    for (unsigned int i = 0; i < 32; ++i)
    {
        move_pos[0] = GET_VAL_BOARD(i, board);
        if (IS_PIECE(move_pos[0]))
        {
            if (IS_WHITE(move_pos[0])) board[1] |= 128;
            if (IS_BLACK(move_pos[0])) board[1] |= 8;
        }
    }
    board[0] = 0;
    if (board[1] & 128) board[0] |= 2;
    if (board[1] & 8) board[0] |= 1;
}

void disp_end_state(unsigned int* board)
{
    system("CLS");
    draw_board(board);
    get_end_state(board);
    if (board[0] & 2 && board[0] & 1) std::cout << std::endl << "Game ended in a draw!" << std::endl << std::endl;
    else if (board[0] & 2) std::cout << std::endl << BG_WHITE_FG_BLACK << "White won!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
    else if (board[0] & 1) std::cout << std::endl << "Black won!" << std::endl << std::endl;
    else if (!board[0]) std::cout << std::endl << "Error occured!" << std::endl << std::endl;
}

////////////////////////////////////////////////////////////////////////////////

int main(int argc, char** argv)
{
    unsigned int board[4];

    unsigned short menu_choice = 0;
    bool player_chosen = false;
    void (*white_player)(unsigned int*, unsigned int*);
    void (*black_player)(unsigned int*, unsigned int*);

    std::cout << BG_WHITE_FG_BLACK << BG_BLACK_FG_WHITE;
    system("cls");
    testing_function();
    while (menu_choice != 2) {
        player_chosen = false;
        std::cout << "1. Start Game - Black Always Begins" << std::endl;
        std::cout << "2. Exit" << std::endl;
        std::cout << "Choice: ";
        std::cin >> menu_choice;
        switch (menu_choice)
        {
        case 1:
            while (!player_chosen)
            {
                system("CLS");
                std::cout << "1. Human Player" << std::endl;
                std::cout << "2. Random Player" << std::endl;
                std::cout << BG_WHITE_FG_BLACK << "White" << BG_BLACK_FG_WHITE << " Player Choice: ";
                std::cin >> menu_choice;
                std::cout << std::endl;
                switch (menu_choice)
                {
                case 1:
                    white_player = &human_player;
                    player_chosen = true;
                    break;
                case 2:
                    white_player = &random_player;
                    player_chosen = true;
                    break;
                default:
                    system("CLS");
                    std::cout << "Please provide a valid choice!" << std::endl << std::endl;
                }
            }
            player_chosen = false;
            while (!player_chosen)
            {
                system("CLS");
                std::cout << "1. Human Player" << std::endl;
                std::cout << "2. Random Player" << std::endl;
                std::cout << "Black Player Choice: ";
                std::cin >> menu_choice;
                std::cout << std::endl;
                switch (menu_choice)
                {
                case 1:
                    black_player = &human_player;
                    player_chosen = true;
                    break;
                case 2:
                    black_player = &random_player;
                    player_chosen = true;
                    break;
                default:
                    system("CLS");
                    std::cout << "Please provide a valid choice!" << std::endl << std::endl;
                }
            }
            menu_choice = 1;
            std::cin.ignore();
            init_board(board);
            game_loop(board, white_player, black_player);
            disp_end_state(board);
            system("pause");
            system("CLS");
            break;
        case 2:
            break;
        default:
            system("CLS");
            std::cout << "Please provide a valid choice!" << std::endl << std::endl;
            break;
        }
    }
    exit(EXIT_SUCCESS);
}

////////////////////////////////////////////////////////////////////////////////
void testing_function()
{
    unsigned int board[4];
    unsigned int move_possibility[3]{};

    //init_board(board);
    //draw_board(board);

    //test_get_move_possibility(board, move_possibility);

    //FLIP_TURN_FLAG(board);
    //test_get_move_possibility(board, move_possibility);
    //std::cout << std::endl;

    //std::cout << std::endl;
    ////test_get_idx_funs(board);
    ////std::cout << std::endl;
    //test_translate_cords_to_idx();
    //test_translate_idx_to_cords();
    //std::cout << std::endl;
    ////test_get_move_possibility_init_loop(board);
    ////std::cout << std::endl;
    ////test_get_piece_move_pos(board, move_possibility, 9, 6);

    init_board(board);
    board[0] = 1074020352;
    board[1] = 1178861808;
    board[2] = 102;
    board[3] = 419424;
    FLIP_TURN_FLAG(board);
    system("CLS");
    draw_board(board);
    test_get_move_possibility(board, move_possibility);
    test_get_piece_move_pos(board, move_possibility, 4);
    game_loop(board, &random_player, &random_player);
    disp_end_state(board);
    system("pause");

    //unsigned int game_count = 1000000;
    //std::chrono::steady_clock::time_point start, finish;
    //std::chrono::duration<double> elapsed;
    //
    //start = std::chrono::high_resolution_clock::now();
    //for (unsigned int i = 0; i < game_count; ++i)
    //{
    //    init_board(board);
    //    game_loop(board, &random_player, &random_player);
    //    get_end_state(board);
    //    //disp_end_state(board);
    //}
    //finish = std::chrono::high_resolution_clock::now();
    //elapsed = (finish - start);

    //std::cout << "Games played: " << game_count << std::endl;
    //std::cout << "Elapsed time: " << elapsed.count() << std::endl;
    //std::cout << "Average time: " << elapsed.count() / game_count << std::endl;
    exit(EXIT_SUCCESS);
}

void test_get_idx_funs(unsigned int board[4])
{
    //test top
    unsigned int tmp = 0;
    std::cout << (32 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (4 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (5 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 1;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (5 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (6 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 3;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (7 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    // test even
    tmp = 4;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (0 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (8 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 5;
    std::cout << std::endl << (0 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (1 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (8 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (9 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 7;
    std::cout << std::endl << (2 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (3 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (10 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (11 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    //test odd
    tmp = 8;
    std::cout << std::endl << (4 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (5 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (12 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (13 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 9;
    std::cout << std::endl << (5 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (6 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (13 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (14 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 11;
    std::cout << std::endl << (7 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (32 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (15 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    //test bottom
    tmp = 28;
    std::cout << std::endl << (32 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (24 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 29;
    std::cout << std::endl << (24 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (25 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;

    tmp = 31;
    std::cout << std::endl << (26 == get_left_upper_idx(tmp)) << ": " << "Left upper to " << tmp << ": " << get_left_upper_idx(tmp);
    std::cout << std::endl << (27 == get_right_upper_idx(tmp)) << ": " << "Right upper to " << tmp << ": " << get_right_upper_idx(tmp);
    std::cout << std::endl << (32 == get_left_lower_idx(tmp)) << ": " << "Left lower to " << tmp << ": " << get_left_lower_idx(tmp);
    std::cout << std::endl << (32 == get_right_lower_idx(tmp)) << ": " << "Right lower to " << tmp << ": " << get_right_lower_idx(tmp);
    std::cout << std::endl;
}

void test_get_move_possibility(unsigned int board[4], unsigned int move_pos[4])
{
    get_move_possibility(board, move_pos);
    std::cout << std::endl << "Possible moves " << (GET_TURN_FLAG(board) ? "for white: " : "for black: ") << (GET_NUM_OF_MOVES(move_pos)) << std::endl;
    std::cout << "Indices of pawns possible to move: ";
    for (unsigned int i = 0; i < GET_NUM_OF_MOVES(move_pos); ++i)
    {
        std::cout << (GET_VAL_MOVE_POS(i, move_pos)) << ' ';
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
    case 7:
        // test 7 - promotion switch turn
        board[0] = 1073759296;
        board[1] = 17412;
        board[2] = 1617168128;
        board[3] = 1711695462;
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
        test_get_move_possibility(board, move_possibility);

        FLIP_TURN_FLAG(board);
        test_get_move_possibility(board, move_possibility);
        std::cout << std::endl;

        std::cout << std::endl;
        test_translate_cords_to_idx();
        std::cout << std::endl;
    }
}

void test_get_piece_move_pos(unsigned int board[4], unsigned int move_pos[4], unsigned int idx)
{
    char cords[2];
    translate_idx_to_cords(idx, cords);

    system("CLS");
    draw_board(board);
    test_translate_cords_to_idx();
    test_translate_idx_to_cords();
    std::cout << std::endl;

    test_get_move_possibility(board, move_pos);

    FLIP_TURN_FLAG(board);
    test_get_move_possibility(board, move_pos);
    std::cout << std::endl;

    get_piece_move_pos(board, move_pos, idx);
    if (GET_NUM_OF_MOVES(move_pos))
    {
        std::cout << "Moves possible for piece on " << cords[0] << cords[1] << " - " << (GET_NUM_OF_MOVES(move_pos)) << std::endl;
        if (GET_BEATING_POS_FLAG(move_pos)) std::cout << "BEATING POSSIBLE!" << std::endl;
        std::cout << "List of tiles to choose from: ";
        unsigned int (*get_dir_idx_ptr)(unsigned int&);
        for (unsigned int dir = 0; dir < 4; ++dir)
        {
            switch (dir)
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
            default: break;
            }
            translate_idx_to_cords(get_dir_idx_ptr(idx), cords);
            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) std::cout << cords[0] << cords[1] << ' ';
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_DIR_FLAG(dir, move_pos)) std::cout << cords[0] << cords[1] << ' ';
        }
        std::cout << std::endl;
    }
    else std::cout << "Movement not possible for piece on " << cords[0] << cords[1] << std::endl;
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

//void move_piece(unsigned int board[4], unsigned int& cur_tile_idx, unsigned int (*get_dir_idx_ptr)(unsigned int&, unsigned int*))
//{
//    if (cur_tile_idx > 31) return;
//
//    unsigned int other_tile_idx = get_dir_idx_ptr(cur_tile_idx, board);
//    if (other_tile_idx == 32) return;
//
//    unsigned int cur_tile = GET_VAL_BOARD_S(cur_tile_idx, board);
//    unsigned int other_tile = GET_VAL_BOARD_S(other_tile_idx, board);
//    if (!IS_PIECE(other_tile))
//    {
//        SET_VAL_BOARD(other_tile_idx, cur_tile, board);
//        SET_VAL_BOARD(cur_tile_idx, 0, board);
//    }
//    else if (IS_WHITE(cur_tile) == IS_WHITE(other_tile)) return;
//    else
//    {
//        unsigned int other_tile_idx2 = get_dir_idx_ptr(other_tile_idx, board);
//        if (GET_VAL_BOARD_S(other_tile_idx2, board)) return;
//        SET_VAL_BOARD(other_tile_idx2, cur_tile, board);
//        SET_VAL_BOARD(other_tile_idx, 0, board);
//        SET_VAL_BOARD(cur_tile_idx, 0, board);
//    }
//}

//void bench(unsigned int board[4])
//{
//    std::chrono::steady_clock::time_point start, finish, start2, finish2;
//    std::chrono::duration<double> elapsed, elapsed2;
//
//    start = std::chrono::high_resolution_clock::now();
//    for (unsigned int i = 0; i < 1000000; ++i)
//    {
//        for (unsigned int idx = 0; idx < 32; ++idx)
//        {
//            // old - GET_VAL_BOARD_S(idx, board);
//            int tmp = GET_VAL_BOARD_S(idx, board) & 3;
//            //int tmp = GET_VAL_BOARD_S(idx, board) << 2;
//            //int tmp = GET_VAL_BOARD_S(idx, board) >> 2;
//            //int tmp = GET_VAL_BOARD_S(idx, board);
//            //int tmp = 16 | 123;
//        }
//    }
//    finish = std::chrono::high_resolution_clock::now();
//    elapsed = (finish - start) / 1000000;
//
//    start2 = std::chrono::high_resolution_clock::now();
//    for (unsigned int i = 0; i < 1000000; ++i)
//    {
//        for (unsigned int idx = 0; idx < 32; ++idx)
//        {
//            // old - GET_VAL_BOARD_S2(idx, board);
//            int tmp = GET_VAL_BOARD_S(idx, board) % 4;
//            //int tmp = GET_VAL_BOARD_S(idx, board) * 4;
//            //int tmp = GET_VAL_BOARD_S(idx, board) / 4;
//            //int tmp = GET_VAL_BOARD_S(idx, board) / 4;
//            //int tmp = 16 ^ 123;
//        }
//    }
//    finish2 = std::chrono::high_resolution_clock::now();
//    elapsed2 = (finish2 - start2) / 1000000;
//
//    //old - std::cout << "Average time for GET_VAL_BOARD_S:  " << elapsed.count() << std::endl;
//    //old - std::cout << "Average time for GET_VAL_BOARD_S2: " << elapsed2.count() << std::endl << std::endl;
//    std::cout << "Average time for & 3:\t" << elapsed.count() << std::endl;
//    std::cout << "Average time for % 4:\t" << elapsed2.count() << std::endl << std::endl;
//    //std::cout << "Average time for << 2:\t" << elapsed.count() << std::endl;
//    //std::cout << "Average time for * 4:\t" << elapsed2.count() << std::endl << std::endl;
//    //std::cout << "Average time for >> 2:\t" << elapsed.count() << std::endl;
//    //std::cout << "Average time for / 4:\t" << elapsed2.count() << std::endl << std::endl;
//    //std::cout << "Average time for get:\t" << elapsed.count() << std::endl;
//    //std::cout << "Average time for get/4:\t" << elapsed2.count() << std::endl << std::endl;
//    //std::cout << "Average time for | :\t" << elapsed.count() << std::endl;
//    //std::cout << "Average time for ^ :\t" << elapsed2.count() << std::endl << std::endl;
//}