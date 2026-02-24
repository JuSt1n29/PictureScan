import os
import sys
import curses
import shutil


def chek_tool(tool_name):
    return shutil.which(tool_name)

def check_all_tool():
    tool_list = ["exiftool", "exiv2", "file", "strings", "hexdump", "steghide", "stegseek", "zsteg", "stegoveritas", "binwalk", "foremost", "pngcheck", "jpeginfo", "zbar"]# - list of tools what will use on our program

    print

    for i in range(len(tool_list)):
        if chek_tool(tool_list[i]):
            print(f"{tool_list[i]} tool found")
        else:
            print(f"{tool_list[i]} tool not fount, please install it")


def menu():
    check_all_tool()

def main():
    #start program
    menu()


if __name__ == '__main__':
    menu()


