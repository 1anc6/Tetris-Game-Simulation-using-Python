
import pygame, sys
from game import Game
from colors import Colors

# Initialize pygame — this sets up the graphics, audio, and input systems
pygame.init()

# Create a font object for displaying text (None = default font, 40 = font size)
title_font = pygame.font.Font(None, 40)

# Render static text surfaces (text, antialias, color)
score_surface = title_font.render("Score", True, Colors.white)
next_surface = title_font.render("Next", True, Colors.white)
game_over_surface = title_font.render("GAME OVER", True, Colors.white)

# Define rectangular areas for where to draw the score and next piece preview
score_rect = pygame.Rect(320, 55, 170, 60)
next_rect = pygame.Rect(320, 215, 170, 180)

# Create the main game window (width = 500px, height = 620px)
screen = pygame.display.set_mode((500, 620))
pygame.display.set_caption("Python Tetris")  # Title bar name

# Clock object to control the frame rate (to keep things running smoothly)
clock = pygame.time.Clock()

# Create an instance of the Game class (contains all game logic)
game = Game()

# Custom user event that will trigger every 200ms to move the piece down automatically
GAME_UPDATE = pygame.USEREVENT
pygame.time.set_timer(GAME_UPDATE, 200)

# --- MAIN GAME LOOP ---
# This infinite loop runs until you close the window.
# It constantly handles input, updates game state, and draws everything on screen.
while True:
    # Process every event that happened since the last frame
    for event in pygame.event.get():
        # If player clicks the close button (X) — quit the game
        if event.type == pygame.QUIT:
            pygame.quit()
            sys.exit()

        # If a key was pressed
        if event.type == pygame.KEYDOWN:

            # If the game is over and player presses any key, restart it
            if game.game_over == True:
                game.game_over = False
                game.reset()

            # Move piece left if LEFT arrow is pressed
            if event.key == pygame.K_LEFT and game.game_over == False:
                game.move_left()

            # Move piece right if RIGHT arrow is pressed
            if event.key == pygame.K_RIGHT and game.game_over == False:
                game.move_right()

            # Move piece down faster if DOWN arrow is pressed
            if event.key == pygame.K_DOWN and game.game_over == False:
                game.move_down()              # Force move piece down by one row
                game.update_score(0, 1)       # Add 1 point for manually moving down

            # Rotate the piece clockwise if UP arrow is pressed
            if event.key == pygame.K_UP and game.game_over == False:
                game.rotate()

        # Automatically move the piece down every 200ms (timer event)
        if event.type == GAME_UPDATE and game.game_over == False:
            game.move_down()

    # --- DRAWING SECTION ---
    # Convert current score number into a text surface
    score_value_surface = title_font.render(str(game.score), True, Colors.white)

    # Fill the entire background with dark blue color
    screen.fill(Colors.dark_blue)

    # Draw the static text labels "Score" and "Next"
    screen.blit(score_surface, (365, 20, 50, 50))
    screen.blit(next_surface, (375, 180, 50, 50))

    # If the game is over, display "GAME OVER" text
    if game.game_over == True:
        screen.blit(game_over_surface, (320, 450, 50, 50))

    # Draw the light blue box around the score area
    pygame.draw.rect(screen, Colors.light_blue, score_rect, 0, 10)

    # Draw the actual numeric score inside the score box (centered)
    screen.blit(score_value_surface, score_value_surface.get_rect(
        centerx=score_rect.centerx,
        centery=score_rect.centery))

    # Draw the light blue box for the "Next" block preview
    pygame.draw.rect(screen, Colors.light_blue, next_rect, 0, 10)

    # Draw the current game state (grid + current block + next block)
    game.draw(screen)

    # Update the display to show the latest frame
    pygame.display.update()

    # Limit the game loop to 60 frames per second
    clock.tick(60)

