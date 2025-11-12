
from grid import Grid
from blocks import *
import random

class Game:
    def __init__(self):
        # The main grid where blocks are placed
        self.grid = Grid()

        # List of all block types (7 Tetris pieces)
        self.blocks = [IBlock(), JBlock(), LBlock(), OBlock(), SBlock(), TBlock(), ZBlock()]

        # Current falling block and the next block to be shown
        self.current_block = self.get_random_block()
        self.next_block = self.get_random_block()

        # Game state variables
        self.game_over = False
        self.score = 0

    # Update the player's score based on lines cleared or manual down movement
    def update_score(self, lines_cleared, move_down_points):
        if lines_cleared == 1:
            self.score += 100
        elif lines_cleared == 2:
            self.score += 300
        elif lines_cleared == 3:
            self.score += 500
        self.score += move_down_points

    # Randomly select a block type (without replacement until all 7 are used)
    def get_random_block(self):
        if len(self.blocks) == 0:
            self.blocks = [IBlock(), JBlock(), LBlock(), OBlock(), SBlock(), TBlock(), ZBlock()]
        block = random.choice(self.blocks)
        self.blocks.remove(block)
        return block

    # Move the current block one cell to the left (if valid)
    def move_left(self):
        self.current_block.move(0, -1)
        if not self.block_inside() or not self.block_fits():
            self.current_block.move(0, 1)  # undo move if invalid

    # Move the current block one cell to the right (if valid)
    def move_right(self):
        self.current_block.move(0, 1)
        if not self.block_inside() or not self.block_fits():
            self.current_block.move(0, -1)  # undo move if invalid

    # Move the current block one cell down
    def move_down(self):
        self.current_block.move(1, 0)
        if not self.block_inside() or not self.block_fits():
            # If it cannot move further, lock it in place
            self.current_block.move(-1, 0)
            self.lock_block()

    # Lock the current block into the grid (after landing)
    def lock_block(self):
        tiles = self.current_block.get_cell_positions()

        # Copy each tile position of the block into the grid
        for position in tiles:
            if self.grid.is_inside(position.row, position.column):
                self.grid.grid[position.row][position.column] = self.current_block.id

        # Get the next block ready
        self.current_block = self.next_block
        self.next_block = self.get_random_block()

        # Clear filled rows and update score
        rows_cleared = self.grid.clear_full_rows()
        if rows_cleared > 0:
            self.update_score(rows_cleared, 0)

        # Check if new block cannot fit → game over
        if not self.block_fits():
            self.game_over = True

    # Reset the game (called when player restarts)
    def reset(self):
        self.grid.reset()
        self.blocks = [IBlock(), JBlock(), LBlock(), OBlock(), SBlock(), TBlock(), ZBlock()]
        self.current_block = self.get_random_block()
        self.next_block = self.get_random_block()
        self.score = 0

    # Check if the current block fits into the grid without overlapping filled cells
    def block_fits(self):
        tiles = self.current_block.get_cell_positions()
        for tile in tiles:
            if not self.grid.is_inside(tile.row, tile.column):
                return False
            if not self.grid.is_empty(tile.row, tile.column):
                return False
        return True

    # Rotate the block if it remains inside the grid and fits properly
    def rotate(self):
        self.current_block.rotate()
        if not self.block_inside() or not self.block_fits():
            self.current_block.undo_rotation()  # revert if invalid

    # Check if all tiles of the current block are inside the visible grid
    def block_inside(self):
        tiles = self.current_block.get_cell_positions()
        for tile in tiles:
            if not self.grid.is_inside(tile.row, tile.column):
                return False
        return True

    # Draw the grid, current block, and next block preview on screen
    def draw(self, screen):
        # Draw main play area (grid + placed blocks)
        self.grid.draw(screen)

        # Draw the currently falling block (offset 11, 11 for positioning)
        self.current_block.draw(screen, 11, 11)

        # Draw the next block in the preview box (position adjusted for shape)
        if self.next_block.id == 3:
            self.next_block.draw(screen, 255, 290)
        elif self.next_block.id == 4:
            self.next_block.draw(screen, 255, 280)
        else:
            self.next_block.draw(screen, 270, 270)
















































