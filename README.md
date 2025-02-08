# Pipex Tester

A comprehensive tester for the 42 Pipex project. This script automates the testing process by checking expected behavior, handling edge cases, and ensuring memory leaks are detected using Valgrind.

## Features

- **Mandatory Tests**  
  - Basic command execution  
  - Handling of non-existent files  
  - Permission errors  
  - Invalid commands  

- **Bonus Tests**  
  - **Multiple pipes:**  
    - Verifies if `pipex` correctly handles multiple pipes, simulating:  
      ```
      ./pipex file1 cmd1 cmd2 cmd3 ... cmdn file2
      ```
      Equivalent to:  
      ```
      < file1 cmd1 | cmd2 | cmd3 ... | cmdn > file2
      ```
  - **Here_doc tests:**  
    - Ensures correct behavior of here_doc functionality  
    - Edge cases with special characters and multiple inputs  
  - **Memory leak detection:**  
    - Uses `valgrind` to check for memory leaks in bonus tests  

## Installation

Clone the repository and navigate to the tester directory:  
```sh
git clone https://github.com/hamzabsst/pipex-tester.git
cd pipex-tester
```
copy the tester into the root of your repo:
for mantadory:
```sh
bash pipex_tester.sh
```
for bonus:
```sh
bash pipex_tester.sh bonus
```
