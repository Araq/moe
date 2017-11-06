#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<stdbool.h>
#include<malloc.h>
#include<signal.h>
#include<ncurses.h>
#include"gapbuffer.h"
//#include<locale.h>

#define KEY_ESC 27
#define COLOR_DEFAULT -1
#define BRIGHT_WHITE 231
#define BRIGHT_GREEN 85 
#define GRAY 245
#define ON 1
#define OFF 0
#define NORMAL_MODE 0
#define INSERT_MODE 1

typedef struct editorStat{
  char filename[256];
  int   y,
        x,
        currentLine,
        numOfLines,
        lineDigit,
        lineDigitSpace,
        mode,
        numOfChange,
        isViewUpdated,
        debugMode;
} editorStat;

// Function prototype
int debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat);
void winInit(WINDOW **win);
void winResizeMove(WINDOW *win, int lines, int columns, int y, int x);
int setCursesColor();
void startCurses();
void signal_handler(int SIG);
void exitCurses();
void winResizeEvent(WINDOW **win, gapBuffer *gb, editorStat *stat);
int saveFile(WINDOW **win, gapBuffer* gb, editorStat *stat);
int countLineDigit(int lineNum);
void printCurrentLine(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printLineNum(WINDOW **win, editorStat *stat, int currentLine, int y);
void printLine(WINDOW **win, gapBuffer* gb, editorStat *stat, int line, int y);
void printLineAll(WINDOW **win, gapBuffer* gb, editorStat *stat);
int commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printStatBarInit(WINDOW **win, editorStat *stat);
void printStatBar(WINDOW **win, editorStat *stat);
int insNewLine(gapBuffer *gb, editorStat *stat, int position);
int insertTab(gapBuffer *gb, editorStat *stat);
int keyUp(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyDown(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyRight(gapBuffer* gb, editorStat* stat);
int keyLeft(gapBuffer* gb, editorStat* stat);
int keyBackSpace(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyEnter(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyA(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyX(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyO(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyD(WINDOW **win, gapBuffer* gb, editorStat* stat);
int moveFirstLine(WINDOW **win, gapBuffer* gb, editorStat* stat);
int moveLastLine(WINDOW **win, gapBuffer* gb, editorStat* stat);
void normalMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
void insertMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
int newFile();
int openFile(char* filename);
