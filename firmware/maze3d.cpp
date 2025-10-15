//==============================================================================
// 3D Console Maze - Raycasting Engine for RISC-V
// Ported from: https://github.com/kaczordon/3D-Console-Maze
//
// Original by kaczordon - Windows console raycaster
// Adapted for bare-metal RISC-V with UART output
//==============================================================================

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <float.h>

//==============================================================================
// C++ Runtime Support (new/delete operators)
//==============================================================================

void* operator new(size_t size) {
    return malloc(size);
}

void* operator new[](size_t size) {
    return malloc(size);
}

void operator delete(void* ptr) noexcept {
    free(ptr);
}

void operator delete[](void* ptr) noexcept {
    free(ptr);
}

void operator delete(void* ptr, size_t) noexcept {
    free(ptr);
}

void operator delete[](void* ptr, size_t) noexcept {
    free(ptr);
}

// UART hardware registers
#define UART_TX_DATA   (*(volatile unsigned int *)0x80000000)
#define UART_TX_STATUS (*(volatile unsigned int *)0x80000004)
#define UART_RX_DATA   (*(volatile unsigned int *)0x80000008)
#define UART_RX_STATUS (*(volatile unsigned int *)0x8000000C)

// Game constants
#define CLOSED ' '
#define DOOR '\xB1'
#define DOORHEIGHT 50
#define CROSS '\xC4'
#define BACKSPACE '\b'
#define STRAIGHT '\xB3'
#define UNDER '\x5F'
#define MAP_HEIGHT 20
#define PPYCENTER 80
#define MAP_WIDTH 20
#define PLANEWIDTH 300
#define PLANEHEIGHT 150
#define WALLHEIGHT 20
#define TILE_SIZE 64
#define PLAYERHEIGHT 16
#define PLAYERDISTANCEPP 277
#define ANGLE60 60
#define ANGLE30 (ANGLE60/2)
#define ANGLE15 (ANGLE30/2)
#define ANGLE90 (ANGLE30*3)
#define ANGLE180 (ANGLE90*2)
#define ANGLE270 (ANGLE90*3)
#define ANGLE360 (ANGLE60*6)
#define ANGLE5 (ANGLE30/6)
#define ANGLE10 (ANGLE5*2)
#define ANGLE0 0
#define ROWSIZE 17
#define COLUMNSIZE 6
#define WALL 1
#define PLAYER 2
#define K_LEFT 75
#define K_RIGHT 77
#define K_UP 72
#define K_DOWN 80
#define PLAYERSPEED 5

// Color codes (simplified for UART)
#define BLACK		0
#define BLUE		1
#define GREEN		2
#define CYAN		3
#define RED		4
#define MAGENTA		5
#define BROWN		6
#define LIGHTGRAY	7
#define DARKGRAY	8
#define LIGHTBLUE	9
#define LIGHTGREEN	10
#define LIGHTCYAN	11
#define LIGHTRED	12
#define LIGHTMAGENTA	13
#define YELLOW		14
#define WHITE		15

//==============================================================================
// UART Functions (replacing Windows console)
//==============================================================================

void uart_putc(char c) {
    while (UART_TX_STATUS & 1);
    UART_TX_DATA = c;
}

void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

int uart_getc_available(void) {
    return UART_RX_STATUS & 1;
}

char uart_getc(void) {
    while (!uart_getc_available());
    return UART_RX_DATA & 0xFF;
}

// conio2 replacement functions
int getch(void) {
    return uart_getc();
}

void gotoxy(int x, int y) {
    // ANSI escape: ESC[y;xH
    char buf[32];
    snprintf(buf, sizeof(buf), "\033[%d;%dH", y, x);
    uart_puts(buf);
}

void textcolor(int color) {
    // ANSI color codes (simplified)
    char buf[16];
    snprintf(buf, sizeof(buf), "\033[%dm", 30 + (color & 7));
    uart_puts(buf);
}

void clrscr(void) {
    uart_puts("\033[2J\033[H");  // Clear screen and home
}

void settitle(const char *title) {
    uart_puts("\033]0;");
    uart_puts(title);
    uart_puts("\007");
}

//==============================================================================
// Tables Class - Angle conversion
//==============================================================================

class Tables {
public:
	Tables() {
		pi = 3.141592653589793f;
	}

	float degreeconverter(float angle) {
		return((float)(angle * pi) / (float)ANGLE180);
	}

private:
	float pi;
};

//==============================================================================
// Player Class
//==============================================================================

class Player {
public:
	Player() {
		playerx = 0;
		playery = 0;
		playerarc = ANGLE270 - 1;
		moves = 0;
		playerspeed = PLAYERSPEED;
	}
	int playerx;
	int playery;
	int moves;
	float playerarc;
	float playeryarc;
	float playerxarc;
	int playerspeed;
	int playerbasex;
	int playerbasey;
};

//==============================================================================
// Buffer Class - Simplified for UART rendering
//==============================================================================

struct CharInfo {
	char ch;
	unsigned char attr;
};

class Buffer {
public:
	Buffer() {
		// Allocate buffer on heap
		buffer = new CharInfo[PLANEWIDTH * PLANEHEIGHT];
		clearBuffer();
	}

	~Buffer() {
		delete[] buffer;
	}

	void clearBuffer() {
		for (int i = 0; i < PLANEWIDTH * PLANEHEIGHT; i++) {
			buffer[i].ch = ' ';
			buffer[i].attr = WHITE;
		}
	}

	void setChar(int x, int y, char ch, unsigned char attr = WHITE) {
		if (x >= 0 && x < PLANEWIDTH && y >= 0 && y < PLANEHEIGHT) {
			buffer[x + y * PLANEWIDTH].ch = ch;
			buffer[x + y * PLANEWIDTH].attr = attr;
		}
	}

	void bufferDraw() {
		// Simple line-by-line UART rendering
		gotoxy(1, 1);
		for (int y = 0; y < PLANEHEIGHT; y++) {
			for (int x = 0; x < PLANEWIDTH; x++) {
				CharInfo &ci = buffer[x + y * PLANEWIDTH];
				uart_putc(ci.ch);
			}
			uart_putc('\n');
		}
	}

private:
	CharInfo *buffer;
};

//==============================================================================
// Map Class - Embedded map data
//==============================================================================

class Map {
public:
	Map(Player* playerclass) {
		height = 20;
		width = 20;
		player = playerclass;
		mapend[0] = 16;
		mapend[1] = 19;
		WallType = '#';
		loadEmbeddedMap();
	}

	int map[20][20];
	int mapend[2];
	int height;
	int width;
	char WallType;

private:
	Player* player;

	void loadEmbeddedMap() {
		// Simple test map
		const char* mapData[] = {
			"####################",
			"#p         #       #",
			"# ######### ##     #",
			"# #       # #      #",
			"# # ##### # # ######",
			"# # #   # # #      #",
			"# # # # # # ###### #",
			"# # # # # #      # #",
			"# # # # # ###### # #",
			"# # # #          # #",
			"# # # ############ #",
			"# # #              #",
			"# # ############## #",
			"# #                #",
			"# ################ #",
			"#                  #",
			"##################-#",
			"#                  #",
			"#                  #",
			"####################"
		};

		for (int i = 0; i < height; i++) {
			for (int j = 0; j < width; j++) {
				char ch = mapData[i][j];
				if (ch == '#')
					map[i][j] = 1;
				else if (ch == '*')
					map[i][j] = 0;
				else if (ch == '@')
					map[i][j] = 3;
				else if (ch == '+')
					map[i][j] = 4;
				else if (ch == '&')
					map[i][j] = 6;
				else if (ch == '%')
					map[i][j] = 7;
				else if (ch == '-') {
					map[i][j] = 0;
					mapend[0] = j;
					mapend[1] = i;
				}
				else if (ch == 'd')
					map[i][j] = 5;
				else if (ch == 'p') {
					map[i][j] = 2;
					player->playerx = (j+1)*TILE_SIZE - (TILE_SIZE / 2);
					player->playery = (i+1)*TILE_SIZE - (TILE_SIZE / 2);
					player->playerbasex = player->playerx;
					player->playerbasey = player->playery;
				}
				else
					map[i][j] = 0;
			}
		}
	}
};

//==============================================================================
// Renderer Class - Raycasting engine (KEEP ORIGINAL LOGIC)
//==============================================================================

class Renderer {
public:
	Renderer(Buffer *buf) {
		table = Tables();
		buffer = buf;
		WallTypeX = 0;
		WallTypeY = 0;
		lastDoor = false;
		closedWall = false;
		miniMapX = 250;
	}

	void rayCast(int PlayerY, int PlayerX, float PlayerArc, Map& map, bool opendoor);
	void drawLab(int x, int drawStart, int drawEnd, Map& map);
	void clearBuffer() { buffer->clearBuffer(); }
	void drawMiniMap(Map& map, Player& player);
	float dist;
	float tempdist;

private:
	Tables table;
	Buffer *buffer;
	int castColumn;
	int firstPY;
	int firstPX;
	int wallMapX;
	int wallMapY;
	int stepY;
	int stepX;
	int nextPY;
	int nextPX;
	int projectedWallHeight;
	int bottomOfWall;
	int topOfWall;
	float finalHWall;
	float finalVWall;
	float distortion;
	bool isWall;
	int i;
	int miniMapX;
	int WallTypeY;
	int WallTypeX;
	bool lastDoor;
	bool closedWall;

	char checkOri(Player& player);
	char wallType(int wall);
	void drawDoor(int x, int drawStart, int drawEnd, Map& map);
	void closeDoor(int x, int drawStart, int drawEnd, Map& map);
};

char Renderer::wallType(int wall) {
	if (wall == 1)
		return '#';
	else if (wall == 3)
		return '@';
	else if (wall == 4)
		return '+';
	else if (wall == 5)
		return DOOR;
	else if (wall == 9)
		return CLOSED;
	else if (wall == 6)
		return '&';
	else if (wall == 7)
		return '%';
	else
		return '#';
}

void Renderer::rayCast(int PlayerY, int PlayerX, float PlayerArc, Map& map, bool opendoor) {
	dist = 0;
	distortion = ANGLE30;
	closedWall = false;
	PlayerArc = PlayerArc + ANGLE30;

	for (castColumn = 0; castColumn < PLANEWIDTH; castColumn += 1) {
		tempdist = dist;
		isWall = false;

		if (PlayerArc > 360)
			PlayerArc = PlayerArc - 360;
		if (PlayerArc < 0)
			PlayerArc = ANGLE360 + PlayerArc;

		//check vertical walls
		if (PlayerArc > 0 && PlayerArc < 180) {
			firstPY = floor(PlayerY / TILE_SIZE) * TILE_SIZE - 1;
			stepY = -TILE_SIZE;
			stepX = TILE_SIZE / tan(table.degreeconverter(PlayerArc + 0.00001f));
		}
		else {
			firstPY = floor(PlayerY / TILE_SIZE) * TILE_SIZE + TILE_SIZE;
			stepY = TILE_SIZE;
			stepX = -(TILE_SIZE / tan(table.degreeconverter(PlayerArc + 0.00001f)));
		}

		firstPX = PlayerX + (int)((PlayerY - firstPY) / tan(table.degreeconverter(PlayerArc + 0.00001f)));

		wallMapX = (int)floor(firstPX / TILE_SIZE);
		wallMapY = (int)floor(firstPY / TILE_SIZE);

		i = 0;
		isWall = false;
		while (true) {
			if (wallMapX >= 0 && wallMapY >= 0 && wallMapX < MAP_WIDTH && wallMapY < MAP_HEIGHT && map.map[wallMapY][wallMapX] == 9 && opendoor == true) {
				map.WallType = CLOSED;
				WallTypeY = map.map[wallMapY][wallMapX];
				isWall = true;
				break;
			}
			if (wallMapX >= 0 && wallMapY >= 0 && wallMapX < MAP_WIDTH && wallMapY < MAP_HEIGHT && (map.map[wallMapY][wallMapX] == 1 || map.map[wallMapY][wallMapX] == 3 || map.map[wallMapY][wallMapX] == 4 || map.map[wallMapY][wallMapX] == 5 || map.map[wallMapY][wallMapX] == 6 || map.map[wallMapY][wallMapX] == 7)) {
				WallTypeY = map.map[wallMapY][wallMapX];
				isWall = true;
				break;
			}
			if (i == 0) {
				nextPY = firstPY + stepY;
				nextPX = firstPX + stepX;
			}
			else {
				nextPY += stepY;
				nextPX += stepX;
			}
			if (nextPX < 0 || nextPY < 0)
				break;

			wallMapX = (int)floor(nextPX / TILE_SIZE);
			wallMapY = (int)floor(nextPY / TILE_SIZE);

			if (wallMapX > MAP_WIDTH || wallMapX < 0 || wallMapY > MAP_HEIGHT || wallMapY < 0) {
				finalVWall = FLT_MAX;
				isWall = false;
				break;
			}
			i++;
		}

		if (isWall && i != 0)
			finalVWall = sqrt(pow((PlayerX - nextPX), 2) + pow((PlayerY - nextPY), 2));
		else if (isWall && i == 0)
			finalVWall = sqrt(pow((PlayerX - firstPX), 2) + pow((PlayerY - firstPY), 2));
		else
			finalVWall = FLT_MAX;

		//check horizontal walls
		if (PlayerArc < ANGLE90 && PlayerArc > ANGLE0) {
			firstPX = floor(PlayerX / TILE_SIZE)*TILE_SIZE + TILE_SIZE;
			stepX = TILE_SIZE;
			stepY = -(TILE_SIZE*tan(table.degreeconverter(PlayerArc + 0.00001f)));
		}
		else if (PlayerArc > ANGLE270 && PlayerArc < ANGLE360) {
			firstPX = floor(PlayerX / TILE_SIZE)*TILE_SIZE + TILE_SIZE;
			stepX = TILE_SIZE;
			stepY = -(TILE_SIZE*tan(table.degreeconverter(PlayerArc + 0.00001f)));
		}
		else if (PlayerArc > ANGLE90 && PlayerArc < ANGLE180) {
			firstPX = floor(PlayerX / TILE_SIZE)*TILE_SIZE - 1;
			stepX = -TILE_SIZE;
			stepY = TILE_SIZE*tan(table.degreeconverter(PlayerArc + 0.00001f));
		}
		else {
			firstPX = floor(PlayerX / TILE_SIZE)*TILE_SIZE - 1;
			stepX = -TILE_SIZE;
			stepY = TILE_SIZE*tan(table.degreeconverter(PlayerArc + 0.00001f));
		}

		firstPY = PlayerY + (PlayerX - firstPX)*tan(table.degreeconverter(PlayerArc+0.00001f));

		wallMapX = (int)floor(firstPX / TILE_SIZE);
		wallMapY = (int)floor(firstPY / TILE_SIZE);
		i = 0;
		isWall = false;
		while (true) {
			if (wallMapX >= 0 && wallMapY >= 0 && wallMapX < MAP_WIDTH && wallMapY < MAP_HEIGHT && map.map[wallMapY][wallMapX] == 9 && opendoor == true) {
				map.WallType = CLOSED;
				WallTypeX = map.map[wallMapY][wallMapX];
				isWall = true;
				break;
			}
			if (wallMapX >= 0 && wallMapY >= 0 && wallMapX < MAP_WIDTH && wallMapY < MAP_HEIGHT && (map.map[wallMapY][wallMapX] == 1 || map.map[wallMapY][wallMapX] == 3 || map.map[wallMapY][wallMapX] == 4 || map.map[wallMapY][wallMapX] == 5 || map.map[wallMapY][wallMapX] == 6 || map.map[wallMapY][wallMapX] == 7)) {
				WallTypeX = map.map[wallMapY][wallMapX];
				isWall = true;
				break;
			}
			if (i == 0) {
				nextPY = firstPY + stepY;
				nextPX = firstPX + stepX;
			}
			else {
				nextPY += stepY;
				nextPX += stepX;
			}
			if (nextPX < 0 || nextPY < 0)
				break;

			wallMapX = (int)floor(nextPX / TILE_SIZE);
			wallMapY = (int)floor(nextPY / TILE_SIZE);

			if (wallMapX > MAP_WIDTH || wallMapX < 0 || wallMapY > MAP_HEIGHT || wallMapY < 0) {
				finalHWall = FLT_MAX;
				isWall = false;
				break;
			}
			i++;
		}

		if (isWall && i != 0)
			finalHWall = sqrt(pow((PlayerX - nextPX), 2) + pow((PlayerY - nextPY), 2));
		else if (isWall && i == 0)
			finalHWall = sqrt(pow((PlayerX - firstPX), 2) + pow((PlayerY - firstPY), 2));
		else
			finalHWall = FLT_MAX;

		if (finalHWall < finalVWall) {
			dist = finalHWall;
			map.WallType = wallType(WallTypeX);
		}
		else {
			dist = finalVWall;
			map.WallType = wallType(WallTypeY);
		}

		dist = dist*cos(table.degreeconverter(distortion));

		projectedWallHeight = (int)((WALLHEIGHT / dist)*(float)PLAYERDISTANCEPP);
		bottomOfWall = PPYCENTER + (int)(projectedWallHeight*0.5f);
		topOfWall = PPYCENTER - (int)(projectedWallHeight*0.5f);

		if (bottomOfWall >= PLANEHEIGHT)
			bottomOfWall = PLANEHEIGHT - 1;
		if (topOfWall < 0)
			topOfWall = 1;

		if (dist > 150) {
			textcolor(DARKGRAY);
		}
		else if (dist >50) {
			textcolor(WHITE);
		}
		else if (dist != tempdist) {
			textcolor(WHITE);
		}

		if (opendoor && map.WallType == DOOR && dist < 64) {
			drawDoor(castColumn, topOfWall, bottomOfWall, map);
			lastDoor = true;
		}
		else {
			drawLab(castColumn, topOfWall, bottomOfWall, map);
		}

		if (opendoor && map.WallType == CLOSED && dist < 64) {
			closeDoor(castColumn, topOfWall, bottomOfWall, map);
			lastDoor = true;
			closedWall = true;
		}

		if (castColumn == 319 && opendoor) {
			if (map.map[(int)floor(PlayerY / TILE_SIZE) + 1][(int)floor(PlayerX / TILE_SIZE)] == 5)
				map.map[(int)floor(PlayerY / TILE_SIZE) + 1][(int)floor(PlayerX / TILE_SIZE)] = 9;
			if (map.map[(int)floor(PlayerY / TILE_SIZE) -1][(int)floor(PlayerX / TILE_SIZE)] == 5)
				map.map[(int)floor(PlayerY / TILE_SIZE) -1][(int)floor(PlayerX / TILE_SIZE)] = 9;
			if (map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) + 1] == 5)
				map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) + 1] = 9;
			if (map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) - 1] == 5)
				map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) - 1] = 9;
		}

		if (castColumn == 319 && opendoor && closedWall) {
			if (map.map[(int)floor(PlayerY / TILE_SIZE) + 1][(int)floor(PlayerX / TILE_SIZE)] == 9)
				map.map[(int)floor(PlayerY / TILE_SIZE) + 1][(int)floor(PlayerX / TILE_SIZE)] = 5;
			if (map.map[(int)floor(PlayerY / TILE_SIZE) - 1][(int)floor(PlayerX / TILE_SIZE)] == 9)
				map.map[(int)floor(PlayerY / TILE_SIZE) - 1][(int)floor(PlayerX / TILE_SIZE)] = 5;
			if (map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) + 1] == 9)
				map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) + 1] = 5;
			if (map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) - 1] == 9)
				map.map[(int)floor(PlayerY / TILE_SIZE)][(int)floor(PlayerX / TILE_SIZE) - 1] = 5;
		}

		distortion -= 0.1875f;
		PlayerArc = PlayerArc - 0.1875f;
	}
}

void Renderer::closeDoor(int x, int drawStart, int drawEnd, Map& map){
	for (int i = drawStart; i < drawEnd; i++) {
		if (i == drawStart)
			buffer->setChar(x, i, CROSS);
		else if (i == drawEnd - 1)
			buffer->setChar(x, i, CROSS);
		else
			buffer->setChar(x, i, DOOR);
	}
}

void Renderer::drawLab(int x, int drawStart, int drawEnd, Map& map) {
	for (int i = drawStart; i < drawEnd; i++) {
		if (i == drawStart)
			buffer->setChar(x, i, CROSS);
		else if (i == drawEnd - 1)
			buffer->setChar(x, i, CROSS);
		else
			buffer->setChar(x, i, map.WallType);
	}
}

void Renderer::drawDoor(int x, int drawStart, int drawEnd, Map& map) {
	for (int i = drawStart; i < drawEnd; i++) {
		if (i > drawEnd - DOORHEIGHT)
			buffer->setChar(x, i, ' ');
		else
			buffer->setChar(x, i, ' ');
	}
}

void Renderer::drawMiniMap(Map& map, Player& player) {
	for (int j = 0; j < map.height; j++) {
		for (int i = 0; i < map.width; i++) {
			if (map.map[i][j] == 1)
				buffer->setChar(j, i+1, '#');
			else if (map.map[i][j] == 3)
				buffer->setChar(j, i+1, '@');
			else if (map.map[i][j] == 4)
				buffer->setChar(j, i+1, '+');
			else if (map.map[i][j] == 2)
				buffer->setChar(j, i+1, checkOri(player));
			else if(map.map[i][j] == 0)
				buffer->setChar(j, i+1, ' ');
			else if (map.map[i][j] == 5)
				buffer->setChar(j, i+1, 'd');
		}
	}
}

char Renderer::checkOri(Player& player) {
	if (player.playerarc > ANGLE270 + ANGLE90 / 2 || player.playerarc < ANGLE90 / 2)
		return '>';
	else if (player.playerarc > ANGLE90 / 2 && player.playerarc < (ANGLE180 - (ANGLE90 / 2)))
		return '^';
	if (player.playerarc < ANGLE270 - (ANGLE90 / 2) && player.playerarc > (ANGLE180 - (ANGLE90 / 2)))
		return '<';
	else
		return 'v';
}

//==============================================================================
// Collision detection
//==============================================================================

bool checkCollision(int x, int y, Map& map) {
	x = (int)floor(x / TILE_SIZE);
	y = (int)floor(y / TILE_SIZE);
	if (map.map[y][x] == 1 || x > MAP_WIDTH || y > MAP_HEIGHT || map.map[y][x] == 3 || map.map[y][x] == 4 || map.map[y][x] == 5)
		return false;
	else
		return true;
}

//==============================================================================
// Main
//==============================================================================

int main() {
	uart_puts("\r\n");
	uart_puts("===========================================\r\n");
	uart_puts("3D Console Maze - Raycasting Engine\r\n");
	uart_puts("RISC-V Bare-Metal Port\r\n");
	uart_puts("===========================================\r\n");
	uart_puts("\r\n");
	uart_puts("Controls:\r\n");
	uart_puts("  Arrow keys: Move/turn\r\n");
	uart_puts("  q: Quit\r\n");
	uart_puts("\r\n");
	uart_puts("Press any key to start...\r\n");
	getch();

	clrscr();
	settitle("MAZE 3D");

	// Initialize game objects
	Player player;
	Map map(&player);
	Map mini(&player);
	Buffer buffer;
	Renderer renderer(&buffer);
	Tables tables;

	bool opendoor = false;
	int a = 0;

	// Game loop
	while (a != 'q') {
		// Render
		renderer.rayCast(player.playery, player.playerx, player.playerarc, map, opendoor);
		if (opendoor) {
			opendoor = false;
			renderer.rayCast(player.playery, player.playerx, player.playerarc, map, opendoor);
		}
		renderer.drawMiniMap(mini, player);
		buffer.bufferDraw();

		// Show stats
		gotoxy(1, 1);
		printf("Moves: %d", player.moves);

		// Input
		a = getch();

		if (a == 'q')
			break;

		if (a == 'd') {
			opendoor = true;
			continue;
		}

		if (a == 0 || a == 224) {
			player.playerxarc = cos(tables.degreeconverter(player.playerarc));
			player.playeryarc = sin(tables.degreeconverter(player.playerarc));

			// Arrow key
			int key = getch();
			switch (key) {
			case K_DOWN:
				if (player.playery + (int)(player.playeryarc*player.playerspeed) > 0 &&
				    player.playery + (int)(player.playeryarc*PLAYERSPEED) < MAP_HEIGHT*TILE_SIZE &&
				    player.playerx - (int)(player.playerxarc*player.playerspeed) > 0 &&
				    player.playerx - (int)(player.playerxarc*player.playerspeed) < TILE_SIZE*MAP_WIDTH &&
				    checkCollision(player.playerx - (int)(player.playerxarc*player.playerspeed),
				                   player.playery + (int)(player.playeryarc*player.playerspeed), map)) {
					mini.map[(int)floor(player.playery / TILE_SIZE)][(int)floor(player.playerx / TILE_SIZE)] = 0;
					player.playery += (int)(player.playeryarc*player.playerspeed);
					player.playerx -= (int)(player.playerxarc*player.playerspeed);
					mini.map[(int)floor(player.playery / TILE_SIZE)][(int)floor(player.playerx / TILE_SIZE)] = 2;
					player.moves += 1;
				}
				break;

			case K_RIGHT:
				if ((player.playerarc -= ANGLE5) < ANGLE0)
					player.playerarc += ANGLE360;
				break;

			case K_UP:
				if (player.playery - (int)(player.playeryarc*player.playerspeed) > 0 &&
				    player.playery - (int)(player.playeryarc*player.playerspeed) < MAP_HEIGHT*TILE_SIZE &&
				    player.playerx + (int)(player.playerxarc*player.playerspeed) > 0 &&
				    player.playerx + (int)(player.playerxarc*player.playerspeed) < TILE_SIZE * MAP_WIDTH &&
				    checkCollision(player.playerx + (int)(player.playerxarc*player.playerspeed),
				                   player.playery - (int)(player.playeryarc*player.playerspeed), map)) {
					mini.map[(int)floor(player.playery / TILE_SIZE)][(int)floor(player.playerx / TILE_SIZE)] = 0;
					player.playery -= (int)(player.playeryarc*player.playerspeed);
					player.playerx += (int)(player.playerxarc*player.playerspeed);
					mini.map[(int)floor(player.playery / TILE_SIZE)][(int)floor(player.playerx / TILE_SIZE)] = 2;
					player.moves += 1;
				}
				break;

			case K_LEFT:
				if ((player.playerarc += ANGLE5) > ANGLE360)
					player.playerarc -= ANGLE360;
				break;
			}
		}

		renderer.clearBuffer();
	}

	uart_puts("\r\n\r\nThanks for playing!\r\n");
	return 0;
}
