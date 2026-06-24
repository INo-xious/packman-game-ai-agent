// =============================================
//  PAC-MAN in Processing (AI Server Edition)
// =============================================
import processing.net.*;

// --- Server ---
Server myServer;

// --- Grid & Cell ---
final int COLS = 21;
final int ROWS = 21;
int CELL;
int OFFSET_X, OFFSET_Y;

// --- Game states ---
final int STATE_MENU    = 0;
final int STATE_PLAYING = 1;
final int STATE_WIN     = 2;
final int STATE_LOSE    = 3;
int gameState = STATE_MENU;

// --- Maze (1=wall, 0=dot, 2=power pellet, 3=empty/ghost house) ---
int[][] maze = {
  {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
  {1,2,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,2,1},
  {1,0,1,1,0,1,1,1,0,1,1,1,0,1,1,1,0,1,1,0,1},
  {1,0,1,1,0,1,1,1,0,1,1,1,0,1,1,1,0,1,1,0,1},
  {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1},
  {1,0,1,1,0,1,0,1,1,1,1,1,1,1,0,1,0,1,1,0,1},
  {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},
  {1,1,1,1,0,1,1,1,3,3,3,3,3,1,1,1,0,1,1,1,1},
  {1,1,1,1,0,1,3,3,3,3,3,3,3,3,3,1,0,1,1,1,1},
  {1,1,1,1,0,1,3,1,1,3,3,3,1,1,3,1,0,1,1,1,1},
  {3,3,3,3,0,3,3,1,3,3,3,3,3,1,3,3,0,3,3,3,3},
  {1,1,1,1,0,1,3,1,1,1,1,1,1,1,3,1,0,1,1,1,1},
  {1,1,1,1,0,1,3,3,3,3,3,3,3,3,3,1,0,1,1,1,1},
  {1,1,1,1,0,1,3,1,1,1,1,1,1,1,3,1,0,1,1,1,1},
  {1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1},
  {1,0,1,1,0,1,1,1,0,1,1,1,0,1,1,1,0,1,1,0,1},
  {1,2,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1,0,2,1},
  {1,1,0,1,0,1,0,1,1,1,1,1,1,1,0,1,0,1,0,1,1},
  {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},
  {1,0,1,1,1,1,1,1,0,1,1,1,0,1,1,1,1,1,1,0,1},
  {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}
};

int[][] mazeOriginal;
int totalDots;
int dotsEaten;

// --- Ghost house centre (for respawn target) ---
final float GHOST_HOME_X = 10.5f;  // grid column (centre of ghost house)
final float GHOST_HOME_Y =  9.5f;  // grid row

// --- Pac-Man ---
float px, py;
float pdx, pdy;
float pNextDx, pNextDy;
float pSpeed;
float mouthAngle;
int   mouthDir;
int   lives;
int   score;
boolean powered;
int   powerTimer;

// --- Game count (for logging) ---
int gameCount = 0;

// --- Ghosts ---
class Ghost {
  float x, y;
  float dx, dy;
  float speed;
  float startX, startY;  // remember spawn position
  int col;
  boolean frightened;
  boolean eaten;
  int scatterTimer;

  Ghost(float startX, float startY, int c) {
    this.startX = startX;
    this.startY = startY;
    x = startX; y = startY;
    col = c;
    dx = -1f; dy = 0f;
    speed = 1.5f;
    frightened = false;
    eaten = false;
    scatterTimer = (int)random(60, 180);
  }

  void update() {
    if (eaten) {
      speed = 3.0f;
    } else if (frightened) {
      speed = 0.8f;
    } else {
      speed = 1.5f;
    }

    float nx = x + dx * speed;
    float ny = y + dy * speed;

    // Wrap candidate position before wall check (tunnel support)
    if (nx < 0)            nx += COLS * CELL;
    if (nx >= COLS * CELL)  nx -= COLS * CELL;

    int gc = gridCol(nx), gr = gridRow(ny);

    if (!wallAt(gc, gr)) {
      x = nx; y = ny;
    } else {
      chooseDirection();
    }

    // --- Eaten ghost: check if it reached the ghost house ---
    if (eaten) {
      float homePixelX = GHOST_HOME_X * CELL;
      float homePixelY = GHOST_HOME_Y * CELL;
      if (dist(x, y, homePixelX, homePixelY) < CELL * 0.6f) {
        eaten = false;
        frightened = false;
        x = startX;
        y = startY;
        dx = -1f;
        dy = 0f;
      }
    }

    scatterTimer--;
    if (scatterTimer <= 0) {
      chooseDirection();
      scatterTimer = (int)random(40, 120);
    }

    // Tunnel wrapping (horizontal) — final safety net
    if (x < 0)            x += COLS * CELL;
    if (x >= COLS * CELL)  x -= COLS * CELL;
  }

  void chooseDirection() {
    float[] ddx = {1f, -1f, 0f, 0f};
    float[] ddy = {0f, 0f, 1f, -1f};
    float best = 999999f;
    int bi = (int)random(4);
    for (int i = 0; i < 4; i++) {
      if (ddx[i] == -dx && ddy[i] == -dy) continue;
      float nx2 = x + ddx[i] * speed * 5f;
      float ny2 = y + ddy[i] * speed * 5f;

      // Wrap candidate before wall check (tunnel support)
      if (nx2 < 0)            nx2 += COLS * CELL;
      if (nx2 >= COLS * CELL)  nx2 -= COLS * CELL;

      int gc2 = gridCol(nx2), gr2 = gridRow(ny2);
      if (wallAt(gc2, gr2)) continue;
      float d;
      if (eaten) {
        // Head back to ghost house
        float homePixelX = GHOST_HOME_X * CELL;
        float homePixelY = GHOST_HOME_Y * CELL;
        d = dist(nx2, ny2, homePixelX, homePixelY);
      } else if (frightened) {
        d = random(1000);
      } else {
        d = dist(nx2, ny2, px, py);
      }
      if (d < best) { best = d; bi = i; }
    }
    dx = ddx[bi]; dy = ddy[bi];
  }

  void draw() {
    pushMatrix();
    translate(OFFSET_X + x, OFFSET_Y + y);

    int cColor = frightened ? color(0, 0, 200) : col;
    if (frightened && powerTimer < 120 && frameCount % 20 < 10) cColor = color(200, 200, 200);
    if (eaten) cColor = color(100, 100, 255, 80);

    noStroke();
    fill(cColor);
    float halfCell = CELL / 2.0f;

    // Body top arc
    arc(0, 0, CELL - 2, CELL - 2, PI, TWO_PI);
    // Body rectangle
    rect(-(halfCell - 1), 0, CELL - 2, halfCell - 2);
    // Skirt triangles (proportional to CELL)
    int w = CELL - 2;
    float skirtBottom = halfCell - 2;
    float skirtPeak   = halfCell - CELL * 0.27f;
    for (int i = 0; i < 3; i++) {
      triangle(
        -w / 2.0f + i * (w / 3.0f), skirtBottom,
        -w / 2.0f + i * (w / 3.0f) + w / 6.0f, skirtPeak,
        -w / 2.0f + (i + 1) * (w / 3.0f), skirtBottom
      );
    }

    // Eyes (proportional to CELL)
    if (!frightened && !eaten) {
      float eyeOffX = CELL * 0.13f;
      float eyeOffY = -CELL * 0.13f;
      float eyeSize = CELL * 0.17f;
      float pupilSize = CELL * 0.1f;
      fill(255);
      ellipse(-eyeOffX, eyeOffY, eyeSize, eyeSize);
      ellipse( eyeOffX, eyeOffY, eyeSize, eyeSize);
      fill(0);
      ellipse(-eyeOffX + dx * 2, eyeOffY + dy * 2, pupilSize, pupilSize);
      ellipse( eyeOffX + dx * 2, eyeOffY + dy * 2, pupilSize, pupilSize);
    }
    // Eaten ghost: show eyes only so player can track it
    if (eaten) {
      float eyeOffX = CELL * 0.13f;
      float eyeOffY = -CELL * 0.13f;
      float eyeSize = CELL * 0.17f;
      float pupilSize = CELL * 0.1f;
      fill(255);
      ellipse(-eyeOffX, eyeOffY, eyeSize, eyeSize);
      ellipse( eyeOffX, eyeOffY, eyeSize, eyeSize);
      fill(0);
      ellipse(-eyeOffX + dx * 2, eyeOffY + dy * 2, pupilSize, pupilSize);
      ellipse( eyeOffX + dx * 2, eyeOffY + dy * 2, pupilSize, pupilSize);
    }

    popMatrix();
  }
}

Ghost[] ghosts;

// =============================================
void setup() {
  size(630, 720);
  CELL = 30;
  OFFSET_X = (width  - COLS * CELL) / 2;
  OFFSET_Y = 60;

  // Save the original maze ONCE at startup
  mazeOriginal = new int[ROWS][COLS];
  for (int r = 0; r < ROWS; r++)
    for (int c = 0; c < COLS; c++)
      mazeOriginal[r][c] = maze[r][c];

  // Start the Network Server on port 5204
  myServer = new Server(this, 5204);

  initGame();
}

void initGame() {
  // Always count dots from the original (pristine) maze
  totalDots = 0;
  for (int r = 0; r < ROWS; r++)
    for (int c = 0; c < COLS; c++)
      if (mazeOriginal[r][c] == 0 || mazeOriginal[r][c] == 2) totalDots++;

  dotsEaten = 0;
  score     = 0;
  lives     = 3;
  powered   = false;
  powerTimer = 0;

  resetPositions();
}

void resetPositions() {
  px = (10 + 0.5f) * CELL;
  py = (16 + 0.5f) * CELL;
  pdx = 0f; pdy = 0f;
  pNextDx = -1f; pNextDy = 0f;
  pSpeed = 2.0f;
  mouthAngle = 0.1f;
  mouthDir = 1;

  ghosts = new Ghost[4];
  ghosts[0] = new Ghost((9  + 0.5f) * CELL, (9  + 0.5f) * CELL, color(255, 0, 0));
  ghosts[1] = new Ghost((10 + 0.5f) * CELL, (9  + 0.5f) * CELL, color(255, 184, 255));
  ghosts[2] = new Ghost((11 + 0.5f) * CELL, (9  + 0.5f) * CELL, color(0, 255, 255));
  ghosts[3] = new Ghost((10 + 0.5f) * CELL, (10 + 0.5f) * CELL, color(255, 184, 82));

  powered = false;
  powerTimer = 0;
}

// =============================================
void draw() {
  background(0);

  // 1. Process ALL network inputs from AI clients
  handleNetworkInput();

  if (gameState == STATE_MENU) {
    drawMenu();
  } else if (gameState == STATE_PLAYING) {
    updateGame();
    drawMaze();
    drawPacman();
    for (Ghost g : ghosts) { g.update(); g.draw(); }
    checkCollisions();
    drawHUD();
    checkWin();
  } else if (gameState == STATE_WIN) {
    drawMaze();
    drawEndScreen("YOU WIN!", color(255, 255, 0));
  } else if (gameState == STATE_LOSE) {
    drawMaze();
    drawEndScreen("GAME OVER", color(255, 50, 50));
  }

  // 2. Broadcast the game state to all connected AIs
  broadcastGameState();
}

// =============================================
//  NETWORKING: Receive AI Commands (reads ALL waiting clients)
// =============================================
void handleNetworkInput() {
  Client c = myServer.available();
  while (c != null) {
    String input = c.readStringUntil('\n');

    if (input != null) {
      try {
        JSONObject json = parseJSONObject(input);
        String action = json.getString("action").toUpperCase();

        // Handle Game Starting / Restarting
        if (action.equals("START") || action.equals("ENTER")) {
          if (gameState != STATE_PLAYING) {
            restoreMaze();
            initGame();
            gameState = STATE_PLAYING;
          }
        }

        // Handle Movement
        if (gameState == STATE_PLAYING) {
          if (action.equals("RIGHT")) { pNextDx =  1f; pNextDy =  0f; }
          if (action.equals("LEFT"))  { pNextDx = -1f; pNextDy =  0f; }
          if (action.equals("DOWN"))  { pNextDx =  0f; pNextDy =  1f; }
          if (action.equals("UP"))    { pNextDx =  0f; pNextDy = -1f; }
        }

      } catch (Exception e) {
        println("Invalid JSON received from AI client.");
      }
    }

    c = myServer.available();  // check for next client
  }
}

// =============================================
//  NETWORKING: Broadcast JSON State
// =============================================
void broadcastGameState() {
  JSONObject state = new JSONObject();

  state.setInt("gameState", gameState);
  state.setInt("score", score);
  state.setInt("lives", lives);
  state.setBoolean("powered", powered);
  state.setInt("powerTimer", powerTimer);

  // Pacman
  JSONObject pacman = new JSONObject();
  pacman.setFloat("px", px);
  pacman.setFloat("py", py);
  pacman.setInt("grid_c", gridCol(px));
  pacman.setInt("grid_r", gridRow(py));
  pacman.setFloat("dx", pdx);
  pacman.setFloat("dy", pdy);
  state.setJSONObject("pacman", pacman);

  // Ghosts
  JSONArray ghostArray = new JSONArray();
  for (int i = 0; i < ghosts.length; i++) {
    JSONObject g = new JSONObject();
    g.setFloat("px", ghosts[i].x);
    g.setFloat("py", ghosts[i].y);
    g.setInt("grid_c", gridCol(ghosts[i].x));
    g.setInt("grid_r", gridRow(ghosts[i].y));
    g.setFloat("dx", ghosts[i].dx);
    g.setFloat("dy", ghosts[i].dy);
    g.setBoolean("frightened", ghosts[i].frightened);
    g.setBoolean("eaten", ghosts[i].eaten);
    ghostArray.setJSONObject(i, g);
  }
  state.setJSONArray("ghosts", ghostArray);

  // Maze
  JSONArray mazeJson = new JSONArray();
  for (int r = 0; r < ROWS; r++) {
    JSONArray row = new JSONArray();
    for (int c2 = 0; c2 < COLS; c2++) {
      row.setInt(c2, maze[r][c2]);
    }
    mazeJson.setJSONArray(r, row);
  }
  state.setJSONArray("maze", mazeJson);

  String jsonString = state.toString();
  jsonString = jsonString.replace("\n", "");
  jsonString = jsonString.replace("\r", "");

  myServer.write(jsonString + "\n");
}

// =============================================
void updateGame() {
  if (powered) {
    powerTimer--;
    if (powerTimer <= 0) {
      powered = false;
      for (Ghost g : ghosts) g.frightened = false;
    }
  }

  // --- Check whether the queued (next) direction is walkable ---
  float tnx = px + pNextDx * pSpeed;
  float tny = py + pNextDy * pSpeed;
  // Wrap candidate BEFORE wall check so the tunnel works
  if (tnx < 0)             tnx += COLS * CELL;
  if (tnx >= COLS * CELL)  tnx -= COLS * CELL;
  if (!wallAt(gridCol(tnx), gridRow(tny))) {
    pdx = pNextDx; pdy = pNextDy;
  }

  // --- Move in the current direction ---
  float nx = px + pdx * pSpeed;
  float ny = py + pdy * pSpeed;
  // Wrap candidate BEFORE wall check so the tunnel works
  if (nx < 0)             nx += COLS * CELL;
  if (nx >= COLS * CELL)  nx -= COLS * CELL;
  if (!wallAt(gridCol(nx), gridRow(ny))) {
    px = nx; py = ny;
  }

  // Tunnel wrapping on actual position — final safety net
  if (px < 0)             px += COLS * CELL;
  if (px >= COLS * CELL)  px -= COLS * CELL;

  int gc = gridCol(px), gr = gridRow(py);
  if (gr >= 0 && gr < ROWS && gc >= 0 && gc < COLS) {
    if (maze[gr][gc] == 0) {
      maze[gr][gc] = 3;
      score += 10;
      dotsEaten++;
    } else if (maze[gr][gc] == 2) {
      maze[gr][gc] = 3;
      score += 50;
      dotsEaten++;
      powered = true;
      powerTimer = 300;
      for (Ghost g : ghosts) { g.frightened = true; g.eaten = false; }
    }
  }

  mouthAngle += 0.15f * mouthDir;
  if (mouthAngle > 0.35f) mouthDir = -1;
  if (mouthAngle < 0.01f) mouthDir =  1;
}

// =============================================
void checkCollisions() {
  for (Ghost g : ghosts) {
    float d = dist(px, py, g.x, g.y);
    if (d < CELL * 0.75f) {
      if (g.frightened && !g.eaten) {
        g.frightened = false;
        g.eaten = true;
        score += 200;
      } else if (!g.eaten) {
        lives--;
        if (lives <= 0) {
          gameState = STATE_LOSE;
          logScore("LOSE");
        } else {
          resetPositions();
        }
      }
    }
  }
}

void checkWin() {
  if (dotsEaten >= totalDots) {
    gameState = STATE_WIN;
    logScore("WIN");
  }
}

// =============================================
//  LOGGING: Append game result to game_log.txt
// =============================================
void logScore(String result) {
  gameCount++;
  String timestamp = year() + "-" + nf(month(), 2) + "-" + nf(day(), 2)
                   + " " + nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2);
  String logLine = "Game #" + gameCount
                 + " | " + timestamp
                 + " | Result: " + result
                 + " | Score: " + score
                 + " | Lives left: " + lives
                 + " | Dots eaten: " + dotsEaten + "/" + totalDots;

  // Append to game_log.txt in the sketch folder
  PrintWriter logFile = null;
  try {
    java.io.FileWriter fw = new java.io.FileWriter(sketchPath("game_log.txt"), true);
    logFile = new PrintWriter(fw);
    logFile.println(logLine);
    println("LOG: " + logLine);
  } catch (Exception e) {
    println("ERROR writing log: " + e.getMessage());
  } finally {
    if (logFile != null) logFile.close();
  }
}

// =============================================
void drawMaze() {
  for (int r = 0; r < ROWS; r++) {
    for (int c = 0; c < COLS; c++) {
      float x = OFFSET_X + c * CELL + CELL / 2;
      float y = OFFSET_Y + r * CELL + CELL / 2;
      int v = maze[r][c];
      if (v == 1) {
        fill(30, 60, 180);
        noStroke();
        rect(OFFSET_X + c * CELL, OFFSET_Y + r * CELL, CELL, CELL, 3);
        stroke(60, 100, 230);
        strokeWeight(1);
        noFill();
        rect(OFFSET_X + c * CELL + 2, OFFSET_Y + r * CELL + 2, CELL - 4, CELL - 4, 2);
        noStroke();
      } else if (v == 0) {
        fill(255, 220, 150);
        noStroke();
        ellipse(x, y, 5, 5);
      } else if (v == 2) {
        // Power pellet: visible 60% of the time (blink effect)
        if (frameCount % 20 < 12) {
          fill(255, 220, 50);
          noStroke();
          ellipse(x, y, 12, 12);
          fill(255, 255, 200, 120);
          ellipse(x, y, 18, 18);
        } else {
          // Dim pellet so player still knows it's there
          fill(255, 220, 50, 60);
          noStroke();
          ellipse(x, y, 10, 10);
        }
      }
    }
  }
}

void drawPacman() {
  pushMatrix();
  translate(OFFSET_X + px, OFFSET_Y + py);

  float angle = 0;
  if (pdx == 1f)  angle = 0f;
  if (pdx == -1f) angle = PI;
  if (pdy == 1f)  angle = HALF_PI;
  if (pdy == -1f) angle = -HALF_PI;
  rotate(angle);

  noStroke();
  fill(255, 220, 0, 60);
  ellipse(0, 0, CELL + 8, CELL + 8);

  fill(255, 220, 0);
  arc(0, 0, CELL - 2, CELL - 2,
      mouthAngle * TWO_PI,
      TWO_PI - mouthAngle * TWO_PI,
      PIE);

  fill(0);
  ellipse(-2, -CELL / 2 + 8, 4, 4);

  popMatrix();
}

void drawHUD() {
  fill(255);
  textSize(18);
  textAlign(LEFT, TOP);
  text("SCORE: " + score, OFFSET_X, 8);

  textAlign(RIGHT, TOP);
  text("LIVES: ", width - OFFSET_X - lives * 22, 8);
  for (int i = 0; i < lives; i++) {
    fill(255, 220, 0);
    noStroke();
    arc(width - OFFSET_X - i * 22, 18, 16, 16, 0.3f, TWO_PI - 0.3f, PIE);
  }

  if (powered) {
    float pct = (float)powerTimer / 300f;
    fill(0, 0, 150);
    rect(OFFSET_X, OFFSET_Y + ROWS * CELL + 5, COLS * CELL, 8, 4);
    fill(0, 100, 255);
    rect(OFFSET_X, OFFSET_Y + ROWS * CELL + 5, COLS * CELL * pct, 8, 4);
  }
}

void drawMenu() {
  textAlign(CENTER, CENTER);
  fill(255, 220, 0);
  textSize(52);
  text("PAC-MAN AI", width / 2, height / 2 - 80);

  float ma = 0.2f * abs(sin(frameCount * 0.08f));
  fill(255, 220, 0);
  noStroke();
  arc(width / 2, height / 2, 60, 60, ma * TWO_PI, TWO_PI - ma * TWO_PI, PIE);

  fill(255);
  textSize(20);
  text("Waiting for AI to send START", width / 2, height / 2 + 70);
  fill(150);
  textSize(14);
  text("(or press ENTER to start manually)", width / 2, height / 2 + 100);
}

void drawEndScreen(String msg, int cColor) {
  fill(0, 0, 0, 170);
  rect(0, 0, width, height);
  textAlign(CENTER, CENTER);
  fill(cColor);
  textSize(48);
  text(msg, width / 2, height / 2 - 40);
  fill(255, 220, 0);
  textSize(22);
  text("Score: " + score, width / 2, height / 2 + 10);
  fill(255);
  textSize(18);
  text("AI send START to play again", width / 2, height / 2 + 50);
}

// =============================================
//  Utility: restore maze from original
// =============================================
void restoreMaze() {
  for (int r = 0; r < ROWS; r++)
    for (int c = 0; c < COLS; c++)
      maze[r][c] = mazeOriginal[r][c];
}

boolean wallAt(int c, int r) {
  if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return true;
  return maze[r][c] == 1;
}

int gridCol(float x) { return (int)(x / CELL); }
int gridRow(float y) { return (int)(y / CELL); }

// =============================================
void keyPressed() {
  if (gameState == STATE_MENU || gameState == STATE_WIN || gameState == STATE_LOSE) {
    if (keyCode == ENTER || keyCode == RETURN) {
      restoreMaze();
      initGame();
      gameState = STATE_PLAYING;
    }
    return;
  }

  if (keyCode == RIGHT || key == 'd' || key == 'D') { pNextDx =  1f; pNextDy = 0f; }
  if (keyCode == LEFT  || key == 'a' || key == 'A') { pNextDx = -1f; pNextDy = 0f; }
  if (keyCode == DOWN  || key == 's' || key == 'S') { pNextDx =  0f; pNextDy = 1f; }
  if (keyCode == UP    || key == 'w' || key == 'W') { pNextDx =  0f; pNextDy =-1f; }
}
