#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TEST_NUM=1
TOTAL_TESTS=0
PASSED_TESTS=0

# Function to check valgrind output properly
check_leaks() {
    local valgrind_out="$1"
    if grep -q "All heap blocks were freed -- no leaks are possible" "$valgrind_out" && \
       ! grep -q "definitely lost" "$valgrind_out" && \
       ! grep -q "indirectly lost" "$valgrind_out" && \
       ! grep -q "ERROR SUMMARY: [^0]" "$valgrind_out"; then
        return 0
    else
        return 1
    fi
}

# Create test directory structure
setup_test_files() {
    mkdir -p test_files/inputs test_files/perms outfiles

    # Basic test files
    echo "Hello World" > test_files/inputs/basic
    echo -e "Multiple\nLines\nOf\nText\nHere" > test_files/inputs/multiline
    echo "" > test_files/inputs/empty
    echo -e "Line1\nLine2\nLine2\nLine3\nLine3\nLine3" > test_files/inputs/duplicates

    # Special content files
    echo -e "Special chars: $HOME $PATH \n * ? [ ] { }" > test_files/inputs/special_chars
    echo -e "#include <stdio.h>\nint main() { return 0; }" > test_files/inputs/code
    echo -e "tab\there\nspace there\n\nblank\rreturn" > test_files/inputs/whitespace
    perl -E 'say "A" x 1000000' > test_files/inputs/large

    # Permission test files
    cp test_files/inputs/basic test_files/perms/no_read
    cp test_files/inputs/basic test_files/perms/no_write
    cp test_files/inputs/basic test_files/perms/no_exec
    chmod 000 test_files/perms/no_read
    chmod 333 test_files/perms/no_write
    chmod 666 test_files/perms/no_exec

    # Create some directories for testing
    mkdir -p test_files/inputs/dir1/dir2
    touch test_files/inputs/dir1/dir2/file

    # Create a symbolic link
    ln -sf test_files/inputs/basic test_files/inputs/symlink
}

# Standard test function for two-command cases
run_test() {
    local test_name="$1"
    local cmd1="$2"
    local cmd2="$3"
    local infile="$4"
    local outfile1="outfiles/out1"
    local outfile2="outfiles/out2"
    local test_passed=1
    local current_test=$TEST_NUM

    TOTAL_TESTS=$((TOTAL_TESTS+1))

    echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Test #${current_test}: ${test_name}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo "Input: $infile"
    echo "Command 1: '$cmd1'"
    echo "Command 2: '$cmd2'"

    # Run standard pipe
    bash -c "< $infile $cmd1 | $cmd2 > $outfile1" 2>outfiles/pipe_err
    local pipe_status=$?

    # Run pipex
    ./pipex "$infile" "$cmd1" "$cmd2" "$outfile2" 2>outfiles/pipex_err
    local pipex_status=$?

    # Compare exit codes
    echo -e "\n${YELLOW}Exit Status Comparison:${NC}"
    echo "Pipe: $pipe_status"
    echo "Pipex: $pipex_status"
    if [ $pipe_status -eq $pipex_status ]; then
        echo -e "${GREEN}✓ Exit codes match${NC}"
    else
        echo -e "${RED}✗ Exit codes differ${NC}"
        test_passed=0
    fi

    # Compare output files
    echo -e "\n${YELLOW}Output Comparison:${NC}"
    if [ -f "$outfile1" ] && [ -f "$outfile2" ]; then
        if diff "$outfile1" "$outfile2" > /dev/null; then
            echo -e "${GREEN}✓ Outputs match${NC}"
        else
            echo -e "${RED}✗ Outputs differ${NC}"
            echo -e "\nPipe output:"
            cat "$outfile1"
            echo -e "\nPipex output:"
            cat "$outfile2"
            echo -e "\nDiff:"
            diff "$outfile1" "$outfile2"
            test_passed=0
        fi
    else
        echo -e "${RED}✗ One or both output files missing${NC}"
        test_passed=0
    fi

    # Check for memory leaks with valgrind
    echo -e "\n${YELLOW}Memory Check:${NC}"
    valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 \
             --track-origins=yes --verbose \
             ./pipex "$infile" "$cmd1" "$cmd2" "$outfile2" 2>outfiles/valgrind_out
    if check_leaks "outfiles/valgrind_out"; then
        echo -e "${GREEN}✓ No memory leaks${NC}"
    else
        echo -e "${RED}✗ Memory issues detected${NC}"
        cat outfiles/valgrind_out
        test_passed=0
    fi

    if [ $test_passed -eq 1 ]; then
        echo -e "${GREEN}✓ Test #${current_test} passed.${NC}"
        PASSED_TESTS=$((PASSED_TESTS+1))
    else
        echo -e "${RED}✗ Test #${current_test} failed.${NC}"
    fi

    TEST_NUM=$((TEST_NUM + 1))
    rm -f "$outfile1" "$outfile2" outfiles/pipe_err outfiles/pipex_err outfiles/valgrind_out
}

# Bonus here_doc test function (only 2 commands allowed)
run_bonus_hd_test() {
    local test_name="$1"
    local heredoc_input="$2"
    local delimiter="$3"
    shift 3
    # The remaining arguments: commands followed by the output file (last arg)
    local outfile="${!#}"
    local test_passed=1
    local current_test=$TEST_NUM

    TOTAL_TESTS=$((TOTAL_TESTS+1))

    echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Bonus Test #${current_test}: ${test_name}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"

    # Run pipex with here_doc mode (simulate user input via echo)
    echo -e "$heredoc_input" | ./pipex here_doc "$delimiter" "$@"
    local pipex_status=$?
    if [ $pipex_status -ne 0 ]; then
        echo -e "${RED}✗ Pipex returned non-zero exit code: $pipex_status${NC}"
        test_passed=0
    fi

    # Memory check with valgrind for bonus here_doc test
    echo -e "\n${YELLOW}Memory Check:${NC}"
    echo -e "$heredoc_input" | valgrind --leak-check=full --show-leak-kinds=all \
             --error-exitcode=1 --track-origins=yes --verbose \
             ./pipex here_doc "$delimiter" "$@" 2> outfiles/valgrind_out_hd
    if check_leaks "outfiles/valgrind_out_hd"; then
         echo -e "${GREEN}✓ No memory leaks${NC}"
    else
         echo -e "${RED}✗ Memory issues detected in bonus here_doc test${NC}"
         cat outfiles/valgrind_out_hd
         test_passed=0
    fi

    if [ -f "$outfile" ] && [ -s "$outfile" ]; then
        echo -e "${GREEN}✓ Output file '$outfile' created and not empty.${NC}"
    else
        echo -e "${RED}✗ Output file '$outfile' missing or empty.${NC}"
        test_passed=0
    fi

    if [ $test_passed -eq 1 ]; then
        echo -e "${GREEN}✓ Bonus Test #${current_test} passed.${NC}"
        PASSED_TESTS=$((PASSED_TESTS+1))
    else
        echo -e "${RED}✗ Bonus Test #${current_test} failed.${NC}"
    fi

    TEST_NUM=$((TEST_NUM + 1))
    rm -f "$outfile" outfiles/valgrind_out_hd
}

# Bonus multiple commands test function (for multiple pipes)
run_test_multi() {
    local test_name="$1"
    local infile="$2"
    shift 2
    # The last argument is the output file; the rest are commands.
    local outfile="${!#}"
    local test_passed=1
    local current_test=$TEST_NUM

    TOTAL_TESTS=$((TOTAL_TESTS+1))

    # Reconstruct a reference pipeline (using bash) from the commands.
    local ref_cmd=""
    local first=1
    local num_args=$#
    local i=1
    for arg in "$@"; do
        if [ $i -eq $num_args ]; then
            break  # skip outfile
        fi
        if [ $first -eq 1 ]; then
            ref_cmd="< $infile $arg"
            first=0
        else
            ref_cmd="$ref_cmd | $arg"
        fi
        i=$((i+1))
    done

    local tmp_outfile="outfiles/tmp_expected_output"
    bash -c "$ref_cmd" > "$tmp_outfile" 2>/dev/null

    echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Bonus Test #${current_test}: ${test_name}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"

    # Run pipex with multiple commands.
    ./pipex "$infile" "$@" 2>/dev/null

    if [ -f "$outfile" ]; then
        if diff "$outfile" "$tmp_outfile" > /dev/null; then
            echo -e "${GREEN}✓ Outputs match for multiple pipes test.${NC}"
        else
            echo -e "${RED}✗ Outputs differ for multiple pipes test.${NC}"
            diff "$outfile" "$tmp_outfile"
            test_passed=0
        fi
    else
        echo -e "${RED}✗ Output file '$outfile' missing.${NC}"
        test_passed=0
    fi

    # Memory check with valgrind for multiple pipes test
    echo -e "\n${YELLOW}Memory Check:${NC}"
    valgrind --leak-check=full --show-leak-kinds=all --error-exitcode=1 \
         --track-origins=yes --verbose \
         ./pipex "$infile" "$@" 2> outfiles/valgrind_out_multi
    if check_leaks "outfiles/valgrind_out_multi"; then
         echo -e "${GREEN}✓ No memory leaks${NC}"
    else
         echo -e "${RED}✗ Memory issues detected in bonus multiple pipes test${NC}"
         cat outfiles/valgrind_out_multi
         test_passed=0
    fi

    if [ $test_passed -eq 1 ]; then
        echo -e "${GREEN}✓ Bonus Test #${current_test} passed.${NC}"
        PASSED_TESTS=$((PASSED_TESTS+1))
    else
        echo -e "${RED}✗ Bonus Test #${current_test} failed.${NC}"
    fi

    TEST_NUM=$((TEST_NUM + 1))
    rm -f "$outfile" "$tmp_outfile" outfiles/valgrind_out_multi
}

# Setup test environment
setup_test_files

# === Standard Tests ===

# Basic functionality tests
run_test "Basic cat and grep" "cat" "grep Hello" "test_files/inputs/basic"
run_test "Basic cat and wc" "cat" "wc -l" "test_files/inputs/multiline"
run_test "Basic sort and uniq" "sort" "uniq" "test_files/inputs/duplicates"

# Empty files and commands
run_test "Empty input file" "cat" "wc -l" "test_files/inputs/empty"
run_test "Empty first command" "" "wc -l" "test_files/inputs/basic"
run_test "Empty second command" "cat" "" "test_files/inputs/basic"
run_test "Both commands empty" "" "" "test_files/inputs/basic"

# Permission tests
run_test "No read permission on input" "cat" "wc -l" "test_files/perms/no_read"
run_test "No write permission on input" "cat" "wc -l" "test_files/perms/no_write"
run_test "No execute permission" "cat" "wc -l" "test_files/perms/no_exec"
run_test "Directory as input" "cat" "wc -l" "test_files/inputs/dir1"

# Non-existent files and commands
run_test "Non-existent input file" "cat" "wc -l" "test_files/inputs/doesnotexist"
run_test "Non-existent first command" "nonexistentcmd" "wc -l" "test_files/inputs/basic"

# Command syntax and arguments
run_test "Invalid flag first command" "ls --invalid" "wc -l" "test_files/inputs/basic"
run_test "Invalid flag second command" "cat" "wc --invalid" "test_files/inputs/basic"
run_test "Multiple flags" "cat -e -n" "grep -i -v hello" "test_files/inputs/basic"

# Special characters and paths
run_test "Commands with spaces" "cat    -e" "grep     Hello" "test_files/inputs/basic"
run_test "Commands with env variables" "cat \$HOME" "grep \$USER" "test_files/inputs/basic"
run_test "Absolute paths" "/bin/cat" "/usr/bin/grep Hello" "test_files/inputs/basic"
run_test "Path with spaces" "cat" "grep Hello" "test_files/inputs/dir1/dir2/file with spaces"
run_test "Symbolic links" "cat" "wc -l" "test_files/inputs/symlink"

# Resource intensive tests
run_test "Large file handling" "cat" "sort" "test_files/inputs/large"
run_test "Memory intensive" "cat" "sort -u" "test_files/inputs/large"

# Special content tests
run_test "Special characters in content" "cat" "grep '*'" "test_files/inputs/special_chars"
run_test "Code file handling" "cat" "grep include" "test_files/inputs/code"
run_test "Whitespace handling" "cat -e" "grep tab" "test_files/inputs/whitespace"

# === Bonus Tests (activated if "bonus" is passed as argument) ===
if [ "$1" = "bonus" ]; then
    echo -e "\n${YELLOW}Running bonus tests...${NC}"

    # Here_doc tests (only 2 commands allowed)
    run_bonus_hd_test "Here_doc test 1" "test\nlines\nEOF" "EOF" "cat" "grep test" "outfiles/here_doc_out"
    run_bonus_hd_test "Here_doc test 2" "test\nEOF\ntest\nEOF" "EOF" "cat" "grep test" "outfiles/here_doc_multi"

    # Bonus tests for multiple pipes:
    run_test_multi "Multiple pipes test 1" "test_files/inputs/multiline" "cat" "grep Lines" "sort" "uniq" "outfiles/multi_pipe_out"
    run_test_multi "Multiple pipes test 2" "test_files/inputs/duplicates" "cat" "sort" "uniq -c" "grep 3" "outfiles/multi_pipe_complex"
fi

# Cleanup
echo -e "\n${YELLOW}Cleaning up test files...${NC}"
rm -rf test_files outfiles

echo -e "\n${GREEN}All tests completed!${NC}"
echo -e "${BLUE}Passed ${PASSED_TESTS} out of ${TOTAL_TESTS} tests.${NC}"
echo -e "\n${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW}	made by hamzabsst${NC}"
echo -e "${YELLOW}	have a good day${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
