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
#include <curand_kernel.h>

// includes, thrust
#include <thrust/host_vector.h>
#include <thrust/device_vector.h>

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
// board indexing: 7 6 5 4 3 2 1 0

//#define DEBUG;
#define MEASURE_TIME
#define THREADS_PER_BLOCK 1024
#define BLOCKS_PER_SEQUENCE_X 1024
#define BLOCKS_PER_SEQUENCE_Y 1
#define BLOCKS_PER_SEQUENCE_Z 1
//////////////////////////////////////////////////////////////////////////////// - board state macros
#define SET_VAL_BOARD(idx, val, board) board[idx >> 3] ^= (board[idx >> 3] ^ val << ((idx & 7) << 2)) & (15 << ((idx & 7) << 2))
#define GET_VAL_BOARD(idx, board) board[idx >> 3] << 28 - ((idx & 7) << 2) >> 28
#define GET_VAL_BOARD_S(idx, board) idx > 31 ? 8 : board[idx >> 3] << 28 - ((idx & 7) << 2) >> 28
//#define IS_EMPTY(tile) (bool)(!tile) -> IS_PIECE instead - ALWAYS
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
#define GET_PIECE_NONBEATING_FLAG(dir, move_pos) (bool)((move_pos[2] << 30 - (dir << 1) >> 30) & 1)
#define SET_PIECE_NONBEATING_FLAG(dir, move_pos) move_pos[2] |= 1 << (dir << 1)
#define GET_PIECE_BEATING_FLAG(dir, move_pos) (bool)((move_pos[2] << 30 - (dir << 1) >> 30) & 2)
#define SET_PIECE_BEATING_FLAG(dir, move_pos) move_pos[2] |= 2 << (dir << 1)
//-------------------------------------------------------------------------------------------------------------------
void init_board(unsigned int board[4]);
void draw_board(unsigned int board[4]);
//////////////////////////////////////////////////////////////////////////////// - get tile idx in specific direction from current
__host__ __device__ unsigned int get_left_upper_idx(unsigned int& cur_tile_idx);
__host__ __device__ unsigned int get_right_upper_idx(unsigned int& cur_tile_idx);
__host__ __device__ unsigned int get_left_lower_idx(unsigned int& cur_tile_idx);
__host__ __device__ unsigned int get_right_lower_idx(unsigned int& cur_tile_idx);
//////////////////////////////////////////////////////////////////////////////// - piece movement
__host__ __device__ void get_move_possibility_loop_fun(unsigned int board[4], unsigned int move_pos[4], unsigned int& cur_idx, unsigned int& moves_idx);
__host__ __device__ void get_move_possibility(unsigned int board[4], unsigned int move_pos[4]);
__host__ __device__ void get_piece_move_pos(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx);
__host__ __device__ void move_piece(unsigned int board[4], unsigned int& cur_tile_idx, unsigned int (*get_dir_idx_ptr)(unsigned int&));
//////////////////////////////////////////////////////////////////////////////// - game loop and players
void game_loop(unsigned int board[4], void (*white_player)(unsigned int*, unsigned int*), void (*black_player)(unsigned int*, unsigned int*));
void human_player(unsigned int board[4], unsigned int move_pos[4]);
void random_player(unsigned int board[4], unsigned int move_pos[4]);
//////////////////////////////////////////////////////////////////////////////// - MCTS
unsigned int simulate_game_CPU(unsigned int board[4]);
unsigned int count_beating_sequences_for_piece_dir(unsigned int board[4], unsigned int cur_tile_idx, unsigned int dir);
void MCTS_CPU_player(unsigned int board[4], unsigned int move_pos[4]);
void MCTS_GPU_player(unsigned int board[4], unsigned int move_pos[4]);
__global__ void MCTS_kernel(const unsigned int* d_first_layer, curandState* states, float* d_results, const unsigned int possible_sequences);
__global__ void setup_kernel(curandState* states);
__device__ float simulate_game_GPU(unsigned int board[4], curandState* states, const unsigned int possible_sequences);
__device__ void random_player_GPU(unsigned int board[4], unsigned int move_pos[4], curandState* state);
//////////////////////////////////////////////////////////////////////////////// - user interaction
void disp_moveable_pieces(unsigned int board[4], unsigned int move_pos[4]);
void disp_possible_dirs(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx);
void get_cords_from_console(char cords[2]);
unsigned int translate_cords_to_idx(const char cords[2]);
void translate_idx_to_cords(unsigned int idx, char cords[2]);
void disp_end_state(unsigned int* board);
//////////////////////////////////////////////////////////////////////////////// - game conclusion
__host__ __device__ void get_end_state(unsigned int board[4]);
//////////////////////////////////////////////////////////////////////////////// - for debugging
void testing_function();
void test_get_idx_funs(unsigned int board[4]);
void test_get_move_possibility(unsigned int board[4], unsigned int move_pos[4]);
void test_get_move_possibility_board_init(unsigned int board[4], unsigned int test_choice);
void test_get_move_possibility_init_loop(unsigned int board[4], int test_choice_lower_bound = 1, int test_choice_upper_bound = 7);
void test_get_piece_move_pos(unsigned int board[4], unsigned int move_pos[4], unsigned int idx);
void test_translate_cords_to_idx();
void test_translate_idx_to_cords();
//void bench(unsigned int board[4]);
//-------------------------------------------------------------------------------------------------------------------

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
    unsigned int left_side_idx = 1; // left_side_idx - labels counter
    bool white_first = true; // flag for alternating colors

    std::cout << BG_BBLUE_FG_BLACK << "   ";
    for (char c = 'A'; c != 'I'; ++c) // print labels
        std::cout << ' ' << c << ' ';
    std::cout << BG_BLACK_FG_WHITE << std::endl;

    for (unsigned int i = 0; i < 4; ++i) // i = board_idx
    {
        for (unsigned int j = 0; j < 8; ++j) // j = tile_in_board_idx
        {
            unsigned int tile = board[i] << (28 - (j << 2)) >> 28;

            if (j == 0 || j == 4) std::cout << BG_BBLUE_FG_BLACK << ' ' << left_side_idx++ << ' '; // print label

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

//////////////////////////////////////////////////////////////////////////////// - get tile idx in specific direction from current (32 - cur_tile_idx out of bound)

__host__ __device__ unsigned int get_left_upper_idx(unsigned int& cur_tile_idx)
{
    if (cur_tile_idx > 31 || !(cur_tile_idx >> 2)) return 32; // second condition checks if is top row
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

__host__ __device__ unsigned int get_right_upper_idx(unsigned int& cur_tile_idx)
{
    if (cur_tile_idx > 31 || !(cur_tile_idx >> 2)) return 32; // second condition checks if is top row
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

__host__ __device__ unsigned int get_left_lower_idx(unsigned int& cur_tile_idx)
{
    if (cur_tile_idx > 31 || (cur_tile_idx >> 2) == 7) return 32; // second condition checks if is bottom row
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

__host__ __device__ unsigned int get_right_lower_idx(unsigned int& cur_tile_idx)
{
    if (cur_tile_idx > 31 || (cur_tile_idx >> 2) == 7) return 32; // second condition checks if is bottom row
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

//////////////////////////////////////////////////////////////////////////////// - piece movement

__host__ __device__ void get_move_possibility_loop_fun(unsigned int board[4], unsigned int move_pos[4], unsigned int& cur_idx, unsigned int& moves_idx)
{
    unsigned int tile, tmp_idx, result;
    tile = GET_VAL_BOARD(cur_idx, board);

    // check if cur_idx tile holds a piece and if it belongs to the currently moving player
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
            if (tmp_idx == 32) continue; // check next 'direction' if out of bound
            result = GET_VAL_BOARD(tmp_idx, board);
            if (IS_PIECE(result) && GET_TURN_FLAG(board) != IS_WHITE(result)) // proceed only if the piece in 'direction' belongs to the opponent
            {
                tmp_idx = get_dir_idx_ptr(tmp_idx);
                if (tmp_idx == 32) continue;
                result = GET_VAL_BOARD(tmp_idx, board);
                if (!IS_PIECE(result)) // check if tile behind opponents's piece is empty
                {
                    if (!GET_BEATING_POS_FLAG(move_pos)) // set beating flag if no beating move was found previously, clear non-beating moves and save new idx
                    {
                        moves_idx = 0;
                        move_pos[0] = move_pos[1] = move_pos[2] = move_pos[3] = 0;
                        SET_BEATING_POS_FLAG(move_pos);
                    }
                    SET_VAL_MOVE_POS(moves_idx, cur_idx, move_pos);
                    ++moves_idx;
                    CLEAR_MOVE_CHECK_GUARD(move_pos); // clear for next iteration
                    return;
                }
            }

            // check if tile in 'direction' is empty, skip if beating possibility is already saved in array 
            // or a non-beating move was previously found for cur_idx tile
            else if (!IS_PIECE(result) && !GET_BEATING_POS_FLAG(move_pos) && !GET_MOVE_CHECK_GUARD(move_pos))
            {
                SET_VAL_MOVE_POS(moves_idx, cur_idx, move_pos);
                ++moves_idx;
                SET_MOVE_CHECK_GUARD(move_pos); // set flag to check only possibility of beating in next iterations
                continue;
            }
        }
        CLEAR_MOVE_CHECK_GUARD(move_pos); // clear for next iteration
    }
}

// Index of tile that can be moved is stored similarly as board representation, but in 8 bits instead of 4 bits
// Additionally move_pos[3] is used for flags and saving number of indexes in the whole array (0 <= n <= 12)
// Flags include - availability of beating for returned indexes, other flag for loop_fun purpose only
__host__ __device__ void get_move_possibility(unsigned int board[4], unsigned int move_pos[4])
{
    unsigned int moves_idx = 0;
    move_pos[0] = move_pos[1] = move_pos[2] = move_pos[3] = 0;
    for (unsigned int i = 0; i < 32; ++i)
        get_move_possibility_loop_fun(board, move_pos, i, moves_idx);
    SET_NUM_OF_MOVES(move_pos, moves_idx); // record number of possible moves
}

// flags in 2 bit pairs: 01 - non-beating move, 10 - beating move, move_pos[2] is used for storing all pairs, 
// the same spots in move_pos[3] as in get_move_possibility are used for beating available flag and number of indexes saved (0 <= n <= 3)
// 0 - left upper, 1 - right upper, 2 - left lower, 3 - right lower
__host__ __device__ void get_piece_move_pos(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx)
{
    unsigned int tile, tmp_idx, result, move_counter = 0;
    move_pos[2] = move_pos[3] = 0; // [0],[1] - not used

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
            if (tmp_idx == 32) continue; // check next 'direction' if out of bound
            result = GET_VAL_BOARD(tmp_idx, board);
            if (IS_PIECE(result) && IS_WHITE(tile) != IS_WHITE(result)) // proceed only if the piece in 'direction' belongs to the opponent
            {
                tmp_idx = get_dir_idx_ptr(tmp_idx);
                if (tmp_idx == 32) continue;
                result = GET_VAL_BOARD(tmp_idx, board);
                if (!IS_PIECE(result)) // check if tile behind opponents's piece is empty
                {
                    if (!GET_BEATING_POS_FLAG(move_pos)) { // set general beating flag if no beating move was found previously, clearing move_pos[2] not necessary
                        move_counter = 0;
                        SET_BEATING_POS_FLAG(move_pos);
                    }
                    SET_PIECE_BEATING_FLAG(direction, move_pos); // set direction beating flag
                    ++move_counter;
                }
            }
            else if (!IS_PIECE(result) && !GET_BEATING_POS_FLAG(move_pos))
            {
                SET_PIECE_NONBEATING_FLAG(direction, move_pos); // set empty tile in direction flag
                ++move_counter;
            }
        }
    }
    SET_NUM_OF_MOVES(move_pos, move_counter);
}

// move piece in the direction specified by get_dir_idx_ptr function pointer, reaching last row promotes Man to King
// !!! - no game logic is checked in this function - correct moves are guaranteed by get_move_possibility and get_piece_move_pos
__host__ __device__ void move_piece(unsigned int board[4], unsigned int& cur_tile_idx, unsigned int (*get_dir_idx_ptr)(unsigned int&))
{
    if (cur_tile_idx > 31) return; // safety guard

    unsigned int other_tile_idx = get_dir_idx_ptr(cur_tile_idx);
    if (other_tile_idx == 32) return; // do not move out of bounds

    unsigned int cur_tile = GET_VAL_BOARD(cur_tile_idx, board);
    if (!IS_PIECE(GET_VAL_BOARD(other_tile_idx, board))) // empty tile - move by one in 'direction', nonbeating
    {
        SET_VAL_BOARD(other_tile_idx, cur_tile, board);
        SET_VAL_BOARD(cur_tile_idx, 0, board);
    }
    else // not empty tile - move by two in 'direction', beating
    {
        if (get_dir_idx_ptr(other_tile_idx) == 32) return; // do not move out of bounds
        SET_VAL_BOARD(other_tile_idx, 0, board);
        SET_VAL_BOARD(cur_tile_idx, 0, board);
        other_tile_idx = get_dir_idx_ptr(other_tile_idx);
        SET_VAL_BOARD(other_tile_idx, cur_tile, board);
    }

    // if reached tile is last row - promote to king
    if ((!IS_KING(cur_tile)) && ((IS_WHITE(cur_tile) && other_tile_idx < 4) || (IS_BLACK(cur_tile) && other_tile_idx > 27)))
        SET_VAL_BOARD(other_tile_idx, (cur_tile | 1), board); // promote to king
}

//////////////////////////////////////////////////////////////////////////////// - game loop and players

void game_loop(unsigned int board[4], void (*white_player)(unsigned int*, unsigned int*), void (*black_player)(unsigned int*, unsigned int*))
{
    unsigned int move_pos[4];
    get_move_possibility(board, move_pos);
    while (0 != (GET_NUM_OF_MOVES(move_pos))) // end game if noone can move
    {
        system("cls");
        draw_board(board);
        std::cout << std::endl << (GET_TURN_FLAG(board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;

        if (GET_TURN_FLAG(board))
            white_player(board, move_pos);
        else
            black_player(board, move_pos);

        get_move_possibility(board, move_pos);
    }
}

void human_player(unsigned int board[4], unsigned int move_pos[4])
{
    unsigned int choosen_idx_tile, choosen_idx_dir, dir;
    char cords[2];
    bool board_beating_flag, beating_sequence_in_progress = false, was_king_before_move;

    // lambdas are for updating displayed information
    auto redraw_beginning = [board]()
    {
        system("cls");
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
    auto redraw_second_stage = [board, move_pos, &choosen_idx_tile, redraw_beginning]()
    {
        redraw_beginning();
        get_piece_move_pos(board, move_pos, choosen_idx_tile);
        disp_possible_dirs(board, move_pos, choosen_idx_tile);
        std::cout << std::endl;
    };

human_player_reset:
    while (true) // piece choice loop
    {
        redraw_first_stage();
        get_cords_from_console(cords);
        choosen_idx_tile = translate_cords_to_idx(cords); // choose tile with piece to be moved
        board_beating_flag = GET_BEATING_POS_FLAG(move_pos);

        get_piece_move_pos(board, move_pos, choosen_idx_tile);
        if (0 == (GET_NUM_OF_MOVES(move_pos)))
        {
            std::cout << std::endl << "This piece cannot move!" << std::endl << "Please choose a different piece!" << std::endl << std::endl;
            system("pause");
            continue;
        }
        else if (board_beating_flag != GET_BEATING_POS_FLAG(move_pos)) // force beating
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
        choosen_idx_dir = translate_cords_to_idx(cords); // choose tile in the dir to move (in distance 1 (diagonally) from idx_tile)

        unsigned int (*get_dir_idx_ptr)(unsigned int&);
        for (dir = 0; dir < 4; ++dir)
        {
            if (dir < 2 && choosen_idx_dir > choosen_idx_tile) // idx_dir > idx_tile only if the chosen tile is in down 'dir', so skip first two (upper) 'dir'
                continue;

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
            default: system("cls"); std::cout << "ERROR - human_player"; system("pause"); exit(EXIT_FAILURE);
            }

            if (choosen_idx_dir != get_dir_idx_ptr(choosen_idx_tile)) // skip dir if idx_dir is not in distance 1
                continue;

            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) // move is beating
            {
                was_king_before_move = IS_KING((GET_VAL_BOARD(choosen_idx_tile, board)));
                move_piece(board, choosen_idx_tile, get_dir_idx_ptr);
                choosen_idx_tile = get_dir_idx_ptr(choosen_idx_dir);
                if (was_king_before_move != (IS_KING((GET_VAL_BOARD(choosen_idx_tile, board))))) // stop beating sequence and end turn if promotion to king happens after a move
                {
                    FLIP_TURN_FLAG(board);
                    return;
                }
                break;
            }
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_NONBEATING_FLAG(dir, move_pos)) // move is nonbeating
            {
                move_piece(board, choosen_idx_tile, get_dir_idx_ptr);
                FLIP_TURN_FLAG(board);
                return;
            }
            std::cout << std::endl << "Impossible move!" << std::endl << "Please choose a different move!" << std::endl << std::endl;
            system("pause");
            if (!beating_sequence_in_progress) // reset to piece choice - if invalid first move was choosen
                goto human_player_reset;
        }
        if (dir == 4) // this is visited only if idx_dir was not in distance 1 from idx_tile
        {
            std::cout << std::endl << "Impossible move!" << std::endl << "Please choose a different move!" << std::endl << std::endl;
            system("pause");
            if (!beating_sequence_in_progress) // reset to piece choice - if invalid first move was choosen
                goto human_player_reset;
            else 
                continue;
        }
        get_piece_move_pos(board, move_pos, choosen_idx_tile);
        if (!GET_BEATING_POS_FLAG(move_pos)) break; // end turn if no more beating possible in current sequence
        beating_sequence_in_progress = true;
    }
    FLIP_TURN_FLAG(board);
}

void random_player(unsigned int board[4], unsigned int move_pos[4])
{
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<> dist(0, 0);
    unsigned int choosen_idx_tile, choosen_idx_dir, dir = 0, dir_idx_upper_bound, dir_idx_counter = 0;
    bool beating_sequence_in_progress = false, was_king_before_move;
    unsigned int (*get_dir_idx_ptr)(unsigned int&);

    // choose tile with piece to be moved
    get_move_possibility(board, move_pos);
    dist = std::uniform_int_distribution<>(0, ((GET_NUM_OF_MOVES(move_pos)) - 1));
    choosen_idx_tile = dist(gen);
    choosen_idx_tile = GET_VAL_MOVE_POS(choosen_idx_tile, move_pos);

    do
    {
        // choose tile in the dir to move (in distance 1 (diagonally) from idx_tile)
        // the rng dir choice is done on the interval [0;n-1] where n is the number of dirs with valid move choices
        get_piece_move_pos(board, move_pos, choosen_idx_tile);
        dir_idx_upper_bound = (GET_NUM_OF_MOVES(move_pos)) - 1; // this is guaranteed o be >= 0 if the game is in progress
        dist = std::uniform_int_distribution<>(0, dir_idx_upper_bound);
        choosen_idx_dir = dist(gen);

        // dir_idx_counter is only incremented if a possible move in 'dir' is encountered but is not the chosen one
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
            default: system("cls"); std::cout << "ERROR - random_player"; system("pause"); exit(EXIT_FAILURE);
            }
            if (dir_idx_counter == choosen_idx_dir); // proceed to make a move after dir is a correct idx
            else if ((GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) || (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_NONBEATING_FLAG(dir, move_pos)))
            {
                ++dir_idx_counter;
                continue;
            }
            else continue;

            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) // move is beating
            {
                was_king_before_move = IS_KING((GET_VAL_BOARD(choosen_idx_tile, board)));
                choosen_idx_dir = get_dir_idx_ptr(choosen_idx_tile);
                move_piece(board, choosen_idx_tile, get_dir_idx_ptr);
                choosen_idx_tile = get_dir_idx_ptr(choosen_idx_dir);
                if (was_king_before_move != (IS_KING((GET_VAL_BOARD(choosen_idx_tile, board))))) // stop beating sequence and end turn if promotion to king happens after a move
                {
                    FLIP_TURN_FLAG(board);
                    return;
                }
                break;
            }
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_NONBEATING_FLAG(dir, move_pos)) // move is nonbeating
            {
                move_piece(board, choosen_idx_tile, get_dir_idx_ptr);
                FLIP_TURN_FLAG(board);
                return;
            }
        }
        if (dir == 4) { system("cls"); std::cout << "ERROR - random_player"; system("pause"); exit(EXIT_FAILURE); }
        get_piece_move_pos(board, move_pos, choosen_idx_tile);
        if (!GET_BEATING_POS_FLAG(move_pos)) break; // end turn if no more beating possible in current sequence
        beating_sequence_in_progress = true;
    } while (beating_sequence_in_progress);
    FLIP_TURN_FLAG(board);
}

//////////////////////////////////////////////////////////////////////////////// - MCTS

unsigned int simulate_game_CPU(unsigned int board[4])
{
    unsigned int move_pos[4];
    get_move_possibility(board, move_pos);
    while (0 != (GET_NUM_OF_MOVES(move_pos))) // end game if noone can move
    {
        random_player(board, move_pos);
        get_move_possibility(board, move_pos);
    }
    get_end_state(board);
    return (board[0] & 2048 ? 2 : 0) | (board[0] & 128 ? 1 : 0);
}

// traverses the sequence tree like DFS
unsigned int count_beating_sequences_for_piece_dir(unsigned int board[4], unsigned int cur_tile_idx, unsigned int dir)
{
    unsigned int piece_pos[4], tmp_board[4]{}, possible_moves = 0, dir_tile_idx;
    bool was_king_before_move;
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
    default: system("cls"); std::cout << "ERROR - count_beating_sequences_for_piece_dir"; system("pause"); exit(EXIT_FAILURE);
    }
    if (GET_BEATING_POS_FLAG(piece_pos) && GET_PIECE_BEATING_FLAG(dir, piece_pos))
    {
        was_king_before_move = IS_KING((GET_VAL_BOARD(cur_tile_idx, tmp_board)));
        dir_tile_idx = get_dir_idx_ptr(cur_tile_idx);
        move_piece(tmp_board, cur_tile_idx, get_dir_idx_ptr);
        cur_tile_idx = get_dir_idx_ptr(dir_tile_idx);
        ++possible_moves;
        if (was_king_before_move != (IS_KING((GET_VAL_BOARD(cur_tile_idx, tmp_board))))) // stop counting if promotion to king happens after a move
        {
            return possible_moves;
        }
        get_piece_move_pos(tmp_board, piece_pos, cur_tile_idx);
        if (GET_BEATING_POS_FLAG(piece_pos)) // check if more beatings in sequence
        {
            possible_moves = 0;
            for (unsigned int dir = 0; dir < 4; ++dir)
                possible_moves += count_beating_sequences_for_piece_dir(tmp_board, cur_tile_idx, dir);
        }
    }
    return possible_moves;
}

void MCTS_CPU_player(unsigned int board[4], unsigned int move_pos[4])
{
    unsigned int*** first_layer, * sequence_count, * selected_tile, choosable_piece_count = 0;
    double** success_rate, ** tries;

#ifdef MEASURE_TIME
    std::chrono::steady_clock::time_point start, stop;
    std::chrono::duration<double, std::milli> elapsed;
    
    start = std::chrono::high_resolution_clock::now();
#endif // MEASURE_TIME

    // allocate memory for first layer
    get_move_possibility(board, move_pos);
    choosable_piece_count = GET_NUM_OF_MOVES(move_pos);
    first_layer = new unsigned int** [choosable_piece_count];
    sequence_count = new unsigned int[choosable_piece_count];
    selected_tile = new unsigned int[choosable_piece_count];
    success_rate = new double* [choosable_piece_count];
    tries = new double* [choosable_piece_count];

    // count needed size and save sequence_count
    for (unsigned int i = 0; i < choosable_piece_count; ++i)
    {
        unsigned int possible_moves = 0;
        selected_tile[i] = GET_VAL_MOVE_POS(i, move_pos);
        if (GET_BEATING_POS_FLAG(move_pos))
            for (unsigned int dir = 0; dir < 4; ++dir)
                possible_moves += count_beating_sequences_for_piece_dir(board, selected_tile[i], dir);
        else
        {
            get_piece_move_pos(board, move_pos, selected_tile[i]);
            possible_moves = GET_NUM_OF_MOVES(move_pos);
            get_move_possibility(board, move_pos);
        }
        sequence_count[i] = possible_moves;
        first_layer[i] = new unsigned int* [sequence_count[i]];
        success_rate[i] = new double[sequence_count[i]];
        tries[i] = new double[sequence_count[i]];

        for (unsigned int j = 0; j < sequence_count[i]; ++j)
        {
            first_layer[i][j] = new unsigned int[4]{};
            success_rate[i][j] = 0;
            tries[i][j] = 0;
        }
    }

    // build first layer
    for (unsigned int i = 0; i < choosable_piece_count; ++i)
    {
        unsigned int tmp_board[4];
        tmp_board[0] = board[0]; tmp_board[1] = board[1]; tmp_board[2] = board[2]; tmp_board[3] = board[3];
        get_piece_move_pos(tmp_board, move_pos, selected_tile[i]);
        if (!GET_BEATING_POS_FLAG(move_pos))
        {
            if (GET_NUM_OF_MOVES(move_pos) > 4) exit(EXIT_FAILURE);
            for (unsigned int j = 0, dir = 0; dir < 4 && j < sequence_count[i]; ++dir)
            {
                tmp_board[0] = board[0]; tmp_board[1] = board[1]; tmp_board[2] = board[2]; tmp_board[3] = board[3];
                if (!GET_PIECE_NONBEATING_FLAG(dir, move_pos)) continue;
                unsigned int (*get_dir_idx_ptr)(unsigned int&);
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
                default: system("cls"); std::cout << "ERROR - MCTS_CPU_player"; system("pause"); exit(EXIT_FAILURE);
                }
                move_piece(tmp_board, selected_tile[i], get_dir_idx_ptr);
                first_layer[i][j][0] = tmp_board[0];
                first_layer[i][j][1] = tmp_board[1];
                first_layer[i][j][2] = tmp_board[2];
                first_layer[i][j][3] = tmp_board[3];
                FLIP_TURN_FLAG(first_layer[i][j]);
                ++j;
            }
        }
        else // this visits nodes in the tree similarly as in count_beating_sequences_for_piece_dir
        {
            unsigned int chaser = 0, j = 0, tmp_count = 0, cur_tile_idx = selected_tile[i];
            while (j < sequence_count[i])
            {
                for (unsigned int dir = 0; dir < 4; ++dir)
                {
                    tmp_count = count_beating_sequences_for_piece_dir(tmp_board, cur_tile_idx, dir);
                    if (!tmp_count) continue;
                    chaser += tmp_count;
                    if (chaser <= j) continue;
                    unsigned int (*get_dir_idx_ptr)(unsigned int&);
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
                    default: system("cls"); std::cout << "ERROR - MCTS_CPU_player"; system("pause"); exit(EXIT_FAILURE);
                    }
                    move_piece(tmp_board, cur_tile_idx, get_dir_idx_ptr);
                    cur_tile_idx = get_dir_idx_ptr(cur_tile_idx);
                    cur_tile_idx = get_dir_idx_ptr(cur_tile_idx);
                }
                chaser = chaser - tmp_count;
                if (((sequence_count[i] - j) != 1 && chaser <= j) || chaser < j) continue;
                first_layer[i][j][0] = tmp_board[0];
                first_layer[i][j][1] = tmp_board[1];
                first_layer[i][j][2] = tmp_board[2];
                first_layer[i][j][3] = tmp_board[3];
                FLIP_TURN_FLAG(first_layer[i][j]);
                cur_tile_idx = selected_tile[i];
                tmp_board[0] = board[0]; tmp_board[1] = board[1]; tmp_board[2] = board[2]; tmp_board[3] = board[3];
                chaser = 0;
                ++j;
            }
        }
    }

#ifdef DEBUG
    // test if layer build correctly - debug
    for (unsigned int i = 0; i < choosable_piece_count; ++i)
    {
        for (unsigned int j = 0; j < sequence_count[i]; ++j)
        {
            system("cls");
            draw_board(board);
            std::cout << std::endl << (GET_TURN_FLAG(board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
            std::cout << std::endl;
            draw_board(first_layer[i][j]);
            std::cout << std::endl << (GET_TURN_FLAG(first_layer[i][j]) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(first_layer[i][j]) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
            system("pause");
        }
    }
#endif // DEBUG

#ifdef MEASURE_TIME
    stop = std::chrono::high_resolution_clock::now();
    elapsed = (stop - start);

    std::cout << "CPU - First Layer Building time: " << elapsed.count() << " ms" << std::endl;
    start = std::chrono::high_resolution_clock::now();
#endif // MEASURE_TIME

    // run simulations
    {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::uniform_int_distribution<> dist1, dist2;
        unsigned int piece_choice, sequence_choice, simulation_result, tmp_board[4];
        dist1 = std::uniform_int_distribution<>(0, choosable_piece_count - 1);

        unsigned int possible_sequences = 0;
        for (unsigned int i = 0; i < choosable_piece_count; ++i)
            possible_sequences += sequence_count[i];

        for (unsigned int i = 0; i < possible_sequences * THREADS_PER_BLOCK * BLOCKS_PER_SEQUENCE_X * BLOCKS_PER_SEQUENCE_Y * BLOCKS_PER_SEQUENCE_Z; ++i)
        {
            piece_choice = dist1(gen);
            dist2 = std::uniform_int_distribution<>(0, sequence_count[piece_choice] - 1);
            sequence_choice = dist2(gen);
            tmp_board[0] = first_layer[piece_choice][sequence_choice][0];
            tmp_board[1] = first_layer[piece_choice][sequence_choice][1];
            tmp_board[2] = first_layer[piece_choice][sequence_choice][2];
            tmp_board[3] = first_layer[piece_choice][sequence_choice][3];

            simulation_result = simulate_game_CPU(tmp_board);
            if (!simulation_result)
                continue;
            else if (simulation_result == 3)
                success_rate[piece_choice][sequence_choice] += 0.5;
            else if ((simulation_result == 2 && GET_TURN_FLAG(board)) || (simulation_result == 1 && GET_TURN_FLAG(board)))
                success_rate[piece_choice][sequence_choice] += 1.0;
            tries[piece_choice][sequence_choice] += 1.0;
        }
    }

#ifdef MEASURE_TIME
    stop = std::chrono::high_resolution_clock::now();
    elapsed = (stop - start);

    std::cout << std::endl << "CPU - Simulation time: " << std::chrono::duration_cast<std::chrono::seconds>(elapsed).count() << " s" << std::endl;
    start = std::chrono::high_resolution_clock::now();
#endif // MEASURE_TIME

    // extract success rate
    for (unsigned int i = 0; i < choosable_piece_count; ++i)
        for (unsigned int j = 0; j < sequence_count[i]; ++j)
            if (tries[i][j] > 0)
                success_rate[i][j] /= tries[i][j];

    // make a move
    {
        double max = -1.0;
        unsigned int idx1, idx2;
        for (unsigned int i = 0; i < choosable_piece_count; ++i)
            for (unsigned int j = 0; j < sequence_count[i]; ++j)
                if (success_rate[i][j] > max)
                {
                    max = success_rate[i][j];
                    idx1 = i; idx2 = j;
                }

        board[0] = first_layer[idx1][idx2][0];
        board[1] = first_layer[idx1][idx2][1];
        board[2] = first_layer[idx1][idx2][2];
        board[3] = first_layer[idx1][idx2][3];
    }

#ifdef MEASURE_TIME
    stop = std::chrono::high_resolution_clock::now();
    elapsed = (stop - start);

    std::cout << std::endl << "CPU - Choosing move time: " << elapsed.count() << " ms" << std::endl << std::endl;
    system("pause");
#endif // MEASURE_TIME

    // deallocate memory for first layer
    for (unsigned int i = 0; i < choosable_piece_count; ++i)
    {
        for (unsigned int j = 0; j < sequence_count[i]; ++j)
            delete[] first_layer[i][j];
        delete[] first_layer[i];
        delete[] success_rate[i];
        delete[] tries[i];
    }
    delete[] first_layer;
    delete[] success_rate;
    delete[] tries;
    delete[] sequence_count;
}

void MCTS_GPU_player(unsigned int board[4], unsigned int move_pos[4])
{
    thrust::host_vector<unsigned int> h_first_layer;
    thrust::device_vector<unsigned int> d_first_layer;
    thrust::device_vector<float> d_results;
    unsigned int* sequence_count, * selected_tile, choosable_piece_count = 0, possible_sequences = 0;
    float* success_rates;

#ifdef MEASURE_TIME
    float elapsedGPU;
    cudaEvent_t startGPU, stopGPU;
    cudaEventCreate(&startGPU);
    cudaEventCreate(&stopGPU);
    std::chrono::steady_clock::time_point startCPU, stopCPU;
    std::chrono::duration<double, std::milli> elapsedCPU;

    startCPU = std::chrono::high_resolution_clock::now();
#endif // MEASURE_TIME

    // allocate memory for computing first layer
    get_move_possibility(board, move_pos);
    choosable_piece_count = GET_NUM_OF_MOVES(move_pos);
    sequence_count = new unsigned int[choosable_piece_count];
    selected_tile = new unsigned int[choosable_piece_count];

    for (unsigned int i = 0; i < choosable_piece_count; ++i)
    {
        unsigned int possible_moves = 0;
        selected_tile[i] = GET_VAL_MOVE_POS(i, move_pos);
        if (GET_BEATING_POS_FLAG(move_pos))
            for (unsigned int dir = 0; dir < 4; ++dir)
                possible_moves += count_beating_sequences_for_piece_dir(board, selected_tile[i], dir);
        else
        {
            get_piece_move_pos(board, move_pos, selected_tile[i]);
            possible_moves = GET_NUM_OF_MOVES(move_pos);
            get_move_possibility(board, move_pos);
        }
        sequence_count[i] = possible_moves;
        possible_sequences += possible_moves;
    }
    // allocate memory for host_vector
    h_first_layer = thrust::host_vector<unsigned int>(static_cast<size_t>(possible_sequences) * 4);
    d_results = thrust::device_vector<float>(static_cast<size_t>(possible_sequences) * THREADS_PER_BLOCK * BLOCKS_PER_SEQUENCE_X * BLOCKS_PER_SEQUENCE_Y * BLOCKS_PER_SEQUENCE_Z);
    success_rates = new float[possible_sequences * BLOCKS_PER_SEQUENCE_X * BLOCKS_PER_SEQUENCE_Y * BLOCKS_PER_SEQUENCE_Z];

    // build first layer
    for (unsigned int host_idx = 0, i = 0; i < choosable_piece_count; ++i)
    {
        unsigned int tmp_board[4];
        tmp_board[0] = board[0]; tmp_board[1] = board[1]; tmp_board[2] = board[2]; tmp_board[3] = board[3];
        get_piece_move_pos(tmp_board, move_pos, selected_tile[i]);
        if (!GET_BEATING_POS_FLAG(move_pos))
        {
            if (GET_NUM_OF_MOVES(move_pos) > 4) exit(EXIT_FAILURE);
            for (unsigned int j = 0, dir = 0; dir < 4 && j < sequence_count[i]; ++dir)
            {
                tmp_board[0] = board[0]; tmp_board[1] = board[1]; tmp_board[2] = board[2]; tmp_board[3] = board[3];
                if (!GET_PIECE_NONBEATING_FLAG(dir, move_pos)) continue;
                unsigned int (*get_dir_idx_ptr)(unsigned int&);
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
                default: system("cls"); std::cout << "ERROR - MCTS_GPU_player"; system("pause"); exit(EXIT_FAILURE);
                }
                move_piece(tmp_board, selected_tile[i], get_dir_idx_ptr);
                FLIP_TURN_FLAG(tmp_board);
                h_first_layer[static_cast<size_t>(host_idx)] = tmp_board[0];
                h_first_layer[static_cast<size_t>(host_idx) + 1] = tmp_board[1];
                h_first_layer[static_cast<size_t>(host_idx) + 2] = tmp_board[2];
                h_first_layer[static_cast<size_t>(host_idx) + 3] = tmp_board[3];
                host_idx += 4;
                ++j;
            }
        }
        else // this visits nodes in the tree similarly as in count_beating_sequences_for_piece_dir
        {
            unsigned int chaser = 0, j = 0, tmp_count = 0, cur_tile_idx = selected_tile[i];
            while (j < sequence_count[i])
            {
                for (unsigned int dir = 0; dir < 4; ++dir)
                {
                    tmp_count = count_beating_sequences_for_piece_dir(tmp_board, cur_tile_idx, dir);
                    if (!tmp_count) continue;
                    chaser += tmp_count;
                    if (chaser <= j) continue;
                    unsigned int (*get_dir_idx_ptr)(unsigned int&);
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
                    default: system("cls"); std::cout << "ERROR - MCTS_GPU_player"; system("pause"); exit(EXIT_FAILURE);
                    }
                    move_piece(tmp_board, cur_tile_idx, get_dir_idx_ptr);
                    cur_tile_idx = get_dir_idx_ptr(cur_tile_idx);
                    cur_tile_idx = get_dir_idx_ptr(cur_tile_idx);
                }
                chaser = chaser - tmp_count;
                if (((sequence_count[i] - j) != 1 && chaser <= j) || chaser < j) continue;
                FLIP_TURN_FLAG(tmp_board);
                h_first_layer[static_cast<size_t>(host_idx)] = tmp_board[0];
                h_first_layer[static_cast<size_t>(host_idx) + 1] = tmp_board[1];
                h_first_layer[static_cast<size_t>(host_idx) + 2] = tmp_board[2];
                h_first_layer[static_cast<size_t>(host_idx) + 3] = tmp_board[3];
                cur_tile_idx = selected_tile[i];
                tmp_board[0] = board[0]; tmp_board[1] = board[1]; tmp_board[2] = board[2]; tmp_board[3] = board[3];
                chaser = 0;
                host_idx += 4;
                ++j;
            }
        }
    }

#ifdef MEASURE_TIME
    stopCPU = std::chrono::high_resolution_clock::now();
    elapsedCPU = (stopCPU - startCPU);

    std::cout << "CPU - First Layer Building time: " << elapsedCPU.count() << " ms" << std::endl;
#endif // MEASURE_TIME

    // deallocate memory used for computing first layer
    delete[] selected_tile;
    delete[] sequence_count;

#ifdef DEBUG
    // test if layer build correctly - debug
    for (unsigned int i = 0; i < possible_sequences; ++i)
    {
        unsigned int tmp_board[4];
        tmp_board[0] = h_first_layer[4 * i];
        tmp_board[1] = h_first_layer[4 * i + 1];
        tmp_board[2] = h_first_layer[4 * i + 2];
        tmp_board[3] = h_first_layer[4 * i + 3];
        system("cls");
        draw_board(board);
        std::cout << std::endl << (GET_TURN_FLAG(board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
        std::cout << std::endl;
        draw_board(tmp_board);
        std::cout << std::endl << (GET_TURN_FLAG(tmp_board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(tmp_board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
        system("pause");
    }
#endif // DEBUG

#ifdef MEASURE_TIME
    cudaEventRecord(startGPU);
#endif // MEASURE_TIME

    // move data to GPU
    d_first_layer = h_first_layer;

    dim3 dimBlock(THREADS_PER_BLOCK, 1, 1);
    dim3 dimGrid(possible_sequences * BLOCKS_PER_SEQUENCE_X, BLOCKS_PER_SEQUENCE_Y, BLOCKS_PER_SEQUENCE_Z);

    thrust::device_vector<curandState> states(64);
    
    // init states for curand
    setup_kernel<<<1, 64>>>(thrust::raw_pointer_cast(states.begin().base()));

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) printf("%s\n", cudaGetErrorString(err));

    cudaDeviceSynchronize();

    // run simulations
    MCTS_kernel<<<dimGrid, dimBlock>>>(thrust::raw_pointer_cast(d_first_layer.begin().base()), thrust::raw_pointer_cast(states.begin().base()), thrust::raw_pointer_cast(d_results.begin().base()), possible_sequences);

    err = cudaGetLastError();
    if (err != cudaSuccess) printf("%s\n", cudaGetErrorString(err));

    cudaDeviceSynchronize();
        
#ifdef MEASURE_TIME
    cudaEventRecord(stopGPU);

    cudaEventSynchronize(stopGPU);
    cudaEventElapsedTime(&elapsedGPU, startGPU, stopGPU);

    std::cout << std::endl << "GPU - Simulation time: " << elapsedGPU << " ms" << std::endl;
    cudaEventRecord(startGPU);
#endif // MEASURE_TIME

    for (unsigned int i = 0; i < possible_sequences * BLOCKS_PER_SEQUENCE_X * BLOCKS_PER_SEQUENCE_Y * BLOCKS_PER_SEQUENCE_Z; ++i)
        success_rates[i] = thrust::reduce(d_results.begin() + (THREADS_PER_BLOCK*i), d_results.begin() + (THREADS_PER_BLOCK * (i+1))) / THREADS_PER_BLOCK.0f;

#ifdef MEASURE_TIME
    cudaEventRecord(stopGPU);

    cudaEventSynchronize(stopGPU);
    cudaEventElapsedTime(&elapsedGPU, startGPU, stopGPU);

    std::cout << std::endl << "GPU - Results Reduction time: " << elapsedGPU << " ms" << std::endl;
    cudaEventDestroy(startGPU);
    cudaEventDestroy(stopGPU);
    startCPU = std::chrono::high_resolution_clock::now();
#endif // MEASURE_TIME

    // sum success_rates for each sequence
    for (unsigned int i = possible_sequences; i < possible_sequences * BLOCKS_PER_SEQUENCE_X * BLOCKS_PER_SEQUENCE_Y * BLOCKS_PER_SEQUENCE_Z; ++i)
        success_rates[i % possible_sequences] += success_rates[i];

    // make a move
    {
        double max = -1.0;
        unsigned int idx;
        for (unsigned int i = 0; i < possible_sequences; ++i)
            if (success_rates[i] > max)
            {
                max = success_rates[i];
                idx = i % possible_sequences;
            }

        board[0] = h_first_layer[4 * idx];
        board[1] = h_first_layer[4 * idx + 1];
        board[2] = h_first_layer[4 * idx + 2];
        board[3] = h_first_layer[4 * idx + 3];
    }

#ifdef MEASURE_TIME
    stopCPU = std::chrono::high_resolution_clock::now();
    elapsedCPU = (stopCPU - startCPU);

    std::cout << std::endl << "CPU - Choosing move time: " << elapsedCPU.count() << " ms" << std::endl << std::endl;
    system("pause");
#endif // MEASURE_TIME

    delete[] success_rates;
}

__global__ void MCTS_kernel(const unsigned int* d_first_layer, curandState* states, float* d_results, const unsigned int possible_sequences)
{
    const unsigned int tid = threadIdx.x;
    const unsigned int bid = blockIdx.x + blockDim.y * (blockIdx.y + blockIdx.z * blockDim.z);
    unsigned int tmp_board[4];
    tmp_board[0] = d_first_layer[4 * (bid % possible_sequences)];
    tmp_board[1] = d_first_layer[4 * (bid % possible_sequences) + 1];
    tmp_board[2] = d_first_layer[4 * (bid % possible_sequences) + 2];
    tmp_board[3] = d_first_layer[4 * (bid % possible_sequences) + 3];
    
    unsigned int simulation_result = simulate_game_GPU(tmp_board, states, possible_sequences);
    if (!simulation_result)
        d_results[tid + THREADS_PER_BLOCK * bid] = 0.0f;
    else if (simulation_result == 3)
        d_results[tid + THREADS_PER_BLOCK * bid] = 0.5f;
    else if ((simulation_result == 2 && GET_TURN_FLAG(tmp_board)) || (simulation_result == 1 && GET_TURN_FLAG(tmp_board)))
        d_results[tid + THREADS_PER_BLOCK * bid] = 1.0f;
}

__global__ void setup_kernel(curandState* states)
{
    int id = threadIdx.x;
    curand_init(1234, id, 0, &states[id]);
}

__device__ float simulate_game_GPU(unsigned int board[4], curandState* states, const unsigned int possible_sequences)
{
    unsigned int id = (blockIdx.x + blockDim.y * (blockIdx.y + blockIdx.z * blockDim.z)) % possible_sequences;
    unsigned int move_pos[4];
    get_move_possibility(board, move_pos);
    while (0 != (GET_NUM_OF_MOVES(move_pos))) // end game if noone can move
    {
        random_player_GPU(board, move_pos, &states[id]);

        get_move_possibility(board, move_pos);
    }
    get_end_state(board);

    return (board[0] & 2048 ? 2 : 0) | (board[0] & 128 ? 1 : 0);
}

__device__ void random_player_GPU(unsigned int board[4], unsigned int move_pos[4], curandState* state)
{
    unsigned int choosen_idx_tile, choosen_idx_dir, dir = 0, dir_idx_upper_bound, dir_idx_counter = 0;
    bool beating_sequence_in_progress = false, was_king_before_move;
    unsigned int (*get_dir_idx_ptr)(unsigned int&);

    // choose tile with piece to be moved
    get_move_possibility(board, move_pos);
    choosen_idx_tile = curand(state) % (GET_NUM_OF_MOVES(move_pos));
    choosen_idx_tile = GET_VAL_MOVE_POS(choosen_idx_tile, move_pos);

    do
    {
        // choose tile in the dir to move(in distance 1 (diagonally)from idx_tile)
        // the rng dir choice is done on the interval [0;n-1] where n is the number of dirs with valid move choices
        get_piece_move_pos(board, move_pos, choosen_idx_tile);
        dir_idx_upper_bound = GET_NUM_OF_MOVES(move_pos);
        choosen_idx_dir = curand(state) % dir_idx_upper_bound;

        // dir_idx_counter is only incremented if a possible move in 'dir' is encountered but is not the chosen one
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
            if (dir_idx_counter == choosen_idx_dir); // proceed to make a move after dir is a correct idx
            else if ((GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) || (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_NONBEATING_FLAG(dir, move_pos)))
            {
                ++dir_idx_counter;
                continue;
            }
            else continue;

            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) // move is beating
            {
                was_king_before_move = IS_KING((GET_VAL_BOARD(choosen_idx_tile, board)));
                choosen_idx_dir = get_dir_idx_ptr(choosen_idx_tile);
                move_piece(board, choosen_idx_tile, get_dir_idx_ptr);
                choosen_idx_tile = get_dir_idx_ptr(choosen_idx_dir);
                if (was_king_before_move != (IS_KING((GET_VAL_BOARD(choosen_idx_tile, board))))) // stop beating sequence and end turn if promotion to king happens after a move
                {
                    FLIP_TURN_FLAG(board);
                    return;
                }
                break;
            }
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_NONBEATING_FLAG(dir, move_pos)) // move is nonbeating
            {
                move_piece(board, choosen_idx_tile, get_dir_idx_ptr);
                FLIP_TURN_FLAG(board);
                return;
            }
        }
        if (dir == 4) return;
        get_piece_move_pos(board, move_pos, choosen_idx_tile);
        if (!GET_BEATING_POS_FLAG(move_pos)) break; // end turn if no more beating possible in current sequence
        beating_sequence_in_progress = true;
    } while (beating_sequence_in_progress);
    FLIP_TURN_FLAG(board);
}

//////////////////////////////////////////////////////////////////////////////// - user interaction

void disp_moveable_pieces(unsigned int board[4], unsigned int move_pos[4])
{
    char cords[2]{ '-' };
    std::cout << "Possible moves for " << (GET_TURN_FLAG(board) ? "white" : "black") << " - " << (GET_NUM_OF_MOVES(move_pos)) << std::endl;
    std::cout << "Tiles with moveable pieces: ";
    get_move_possibility(board, move_pos);
    for (unsigned int i = 0; i < GET_NUM_OF_MOVES(move_pos); ++i)
    {
        translate_idx_to_cords((GET_VAL_MOVE_POS(i, move_pos)), cords);
        std::cout << cords[0] << cords[1] << ' ';
    }
    std::cout << std::endl;
}

void disp_possible_dirs(unsigned int board[4], unsigned int move_pos[4], unsigned int& idx)
{
    char cords[2]{ '-' };
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
            default: system("cls"); std::cout << "ERROR - disp_possible_dirs"; system("pause"); exit(EXIT_FAILURE);
            }
            translate_idx_to_cords(get_dir_idx_ptr(idx), cords);
            if (GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_BEATING_FLAG(dir, move_pos)) std::cout << cords[0] << cords[1] << ' ';
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_NONBEATING_FLAG(dir, move_pos)) std::cout << cords[0] << cords[1] << ' ';
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

void disp_end_state(unsigned int* board)
{
    system("cls");
    draw_board(board);
    get_end_state(board);
    if (board[0] & 2048 && board[0] & 128) std::cout << std::endl << "Game ended in a draw!" << std::endl << std::endl;
    else if (board[0] & 2048) std::cout << std::endl << BG_WHITE_FG_BLACK << "White won!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
    else if (board[0] & 128) std::cout << std::endl << "Black won!" << std::endl << std::endl;
    else if (!board[0]) std::cout << std::endl << "Error occured!" << std::endl << std::endl;
}

//////////////////////////////////////////////////////////////////////////////// - game conclusion

// saves end state in board[0], none - error, 1xxx xxxxx - black win, 1xxx xxxx xxxx - white win, both win - draw
// after extracting: 0 - error, 1 - black win, 2 - white win, 3 - draw
// to extract - (board[0] & 2048 ? 2 : 0) | (board[0] & 128 ? 1 : 0)
__host__ __device__ void get_end_state(unsigned int board[4])
{
    unsigned int move_pos[4];

    get_move_possibility(board, move_pos);
    for (unsigned int i = 0; i < 32; ++i)
    {
        move_pos[0] = GET_VAL_BOARD(i, board);
        if (IS_PIECE(move_pos[0]))
        {
            if (IS_WHITE(move_pos[0])) board[0] |= 2048;
            if (IS_BLACK(move_pos[0])) board[0] |= 128;
        }
    }
}

//////////////////////////////////////////////////////////////////////////////// - main

int main(int argc, char** argv)
{
    unsigned int board[4];

    unsigned short menu_choice = 0;
    bool player_chosen = false;
    void (*white_player)(unsigned int*, unsigned int*);
    void (*black_player)(unsigned int*, unsigned int*);

    std::cout << BG_WHITE_FG_BLACK << BG_BLACK_FG_WHITE;
    system("cls");
    //testing_function();
    while (menu_choice != 2) {
        player_chosen = false;
        std::cout << BG_BBLUE_FG_BLACK << "!!! Monte-Carlo Tree Search Checkers !!!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
        std::cout << "1. Start Game - Black Always Begins" << std::endl;
        std::cout << "2. Exit" << std::endl;
        std::cout << "Choice: ";
        std::cin >> menu_choice;
        switch (menu_choice)
        {
        case 1:
            while (!player_chosen)
            {
                system("cls");
                std::cout << "1. Human Player" << std::endl;
                std::cout << "2. MCTS_CPU Player" << std::endl;
                std::cout << "3. MCTS_GPU Player" << std::endl;
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
                    white_player = &MCTS_CPU_player;
                    player_chosen = true;
                    break;
                case 3:
                    white_player = &MCTS_GPU_player;
                    player_chosen = true;
                    break;
                default:
                    system("cls");
                    std::cout << "Please provide a valid choice!" << std::endl << std::endl;
                }
            }
            player_chosen = false;
            while (!player_chosen)
            {
                system("cls");
                std::cout << "1. Human Player" << std::endl;
                std::cout << "2. MCTS_CPU Player" << std::endl;
                std::cout << "3. MCTS_GPU Player" << std::endl;
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
                    black_player = &MCTS_CPU_player;
                    player_chosen = true;
                    break;
                case 3:
                    black_player = &MCTS_GPU_player;
                    player_chosen = true;
                    break;
                default:
                    system("cls");
                    std::cout << "Please provide a valid choice!" << std::endl << std::endl;
                }
            }
            menu_choice = 1;
            std::cin.ignore();
            init_board(board);
            game_loop(board, white_player, black_player);
            disp_end_state(board);
            system("pause");
            system("cls");
            break;
        case 2:
            break;
        default:
            system("cls");
            std::cout << "Please provide a valid choice!" << std::endl << std::endl;
            break;
        }
    }
    exit(EXIT_SUCCESS);
}

//////////////////////////////////////////////////////////////////////////////// - for debugging
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
    board[0] = 6569984;
    board[1] = 0;
    board[2] = 0;
    board[3] = 0;
    FLIP_TURN_FLAG(board);
    system("cls");
    draw_board(board);
    std::cout << std::endl << (GET_TURN_FLAG(board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
    get_move_possibility(board, move_possibility);
    disp_moveable_pieces(board, move_possibility);
    unsigned int idx = 5;
    disp_possible_dirs(board, move_possibility, idx);
    random_player(board, move_possibility);
    //move_piece(board, idx, &get_left_upper_idx);
    //move_piece(board, idx, &get_right_upper_idx);
    draw_board(board);
    //MCTS_GPU_player(board, move_possibility);
    //draw_board(board);
    //std::cout << std::endl << (GET_TURN_FLAG(board) ? BG_WHITE_FG_BLACK : BG_BLACK_FG_WHITE) << (GET_TURN_FLAG(board) ? "White" : "Black") << "'s turn!" << BG_BLACK_FG_WHITE << std::endl << std::endl;
    //game_loop(board, MCTS_GPU_player, MCTS_GPU_player);
    //disp_end_state(board);
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

void test_get_move_possibility_init_loop(unsigned int board[4], int test_choice_lower_bound, int test_choice_upper_bound)
{
    for (int i = test_choice_lower_bound; i < test_choice_upper_bound; ++i)
    {
        system("pause");
        test_get_move_possibility_board_init(board, i);
        system("cls");
        draw_board(board);

        std::cout << "Running test " << i << std::endl;

        unsigned int move_possibility[3]{};
        test_get_move_possibility(board, move_possibility);

        FLIP_TURN_FLAG(board);
        test_get_move_possibility(board, move_possibility);
        FLIP_TURN_FLAG(board);
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

    system("cls");
    draw_board(board);
    test_translate_cords_to_idx();
    test_translate_idx_to_cords();
    std::cout << std::endl;

    test_get_move_possibility(board, move_pos);

    FLIP_TURN_FLAG(board);
    test_get_move_possibility(board, move_pos);
    FLIP_TURN_FLAG(board);
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
            else if (!GET_BEATING_POS_FLAG(move_pos) && GET_PIECE_NONBEATING_FLAG(dir, move_pos)) std::cout << cords[0] << cords[1] << ' ';
        }
        std::cout << std::endl;
    }
    else std::cout << "Movement not possible for piece on " << cords[0] << cords[1] << std::endl;
}

void test_translate_cords_to_idx()
{
    char cords[2] = { 'A', '1' };
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