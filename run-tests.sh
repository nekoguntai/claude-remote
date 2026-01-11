#!/usr/bin/env bash
#
# run-tests.sh - Run the test suite for claude-remote
#
# Usage:
#   ./run-tests.sh           # Run all tests
#   ./run-tests.sh unit      # Run unit tests only
#   ./run-tests.sh smoke     # Run smoke tests only
#   ./run-tests.sh lint      # Run ShellCheck only
#   ./run-tests.sh --install # Install bats-core
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Install bats-core
install_bats() {
    print_header "Installing bats-core"

    if command -v bats &>/dev/null; then
        print_success "bats is already installed: $(bats --version)"
        return 0
    fi

    # Try npm first (works without sudo)
    if command -v npm &>/dev/null; then
        echo "Installing via npm..."
        npm install -g bats 2>/dev/null && return 0
    fi

    # Try homebrew
    if command -v brew &>/dev/null; then
        echo "Installing via Homebrew..."
        brew install bats-core && return 0
    fi

    # Try apt
    if command -v apt-get &>/dev/null; then
        echo "Installing via apt (requires sudo)..."
        sudo apt-get update && sudo apt-get install -y bats && return 0
    fi

    # Manual install
    echo "Installing from source..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    git clone --depth 1 https://github.com/bats-core/bats-core.git "$tmp_dir/bats-core"
    cd "$tmp_dir/bats-core"

    if [[ -w /usr/local/bin ]]; then
        ./install.sh /usr/local
    else
        mkdir -p "$HOME/.local"
        ./install.sh "$HOME/.local"
        export PATH="$HOME/.local/bin:$PATH"
    fi

    rm -rf "$tmp_dir"
    print_success "bats-core installed"
}

# Run ShellCheck
run_shellcheck() {
    print_header "Running ShellCheck"

    if ! command -v shellcheck &>/dev/null; then
        print_warning "ShellCheck not installed. Install with:"
        echo "    apt install shellcheck  # Debian/Ubuntu"
        echo "    brew install shellcheck # macOS"
        return 1
    fi

    local scripts=(
        "install.sh"
        "uninstall.sh"
        "scripts/claude-session"
        "scripts/web-terminal"
        "scripts/ttyd-wrapper"
        "scripts/status"
        "scripts/maintenance"
    )

    local failed=0
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            echo -n "Checking $script... "
            if shellcheck -S warning "$script" 2>/dev/null; then
                print_success "OK"
            else
                print_error "FAILED"
                shellcheck -S warning "$script"
                failed=1
            fi
        fi
    done

    return $failed
}

# Run syntax checks
run_syntax_check() {
    print_header "Checking Bash Syntax"

    local scripts=(
        "install.sh"
        "uninstall.sh"
        "scripts/claude-session"
        "scripts/web-terminal"
        "scripts/ttyd-wrapper"
        "scripts/status"
        "scripts/maintenance"
    )

    local failed=0
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            echo -n "Syntax check: $script... "
            if bash -n "$script" 2>/dev/null; then
                print_success "OK"
            else
                print_error "FAILED"
                bash -n "$script"
                failed=1
            fi
        fi
    done

    return $failed
}

# Run Docker integration tests
run_docker_tests() {
    print_header "Running Docker Integration Tests"

    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed"
        return 1
    fi

    local compose_file="tests/docker/docker-compose.test.yml"

    if [[ ! -f "$compose_file" ]]; then
        print_error "Docker compose file not found: $compose_file"
        return 1
    fi

    echo "Building test containers..."
    docker-compose -f "$compose_file" build

    echo ""
    echo "Running Debian tests..."
    if docker-compose -f "$compose_file" run --rm test-debian; then
        print_success "Debian tests passed"
    else
        print_error "Debian tests failed"
    fi

    echo ""
    echo "Running Fedora tests..."
    if docker-compose -f "$compose_file" run --rm test-fedora; then
        print_success "Fedora tests passed"
    else
        print_error "Fedora tests failed"
    fi

    # Cleanup
    docker-compose -f "$compose_file" down --rmi local 2>/dev/null || true
}

# Run bats tests
run_bats_tests() {
    local suite="$1"

    if ! command -v bats &>/dev/null; then
        print_error "bats is not installed. Run: $0 --install"
        return 1
    fi

    case "$suite" in
        unit)
            print_header "Running Unit Tests"
            bats tests/unit/*.bats
            ;;
        smoke)
            print_header "Running Smoke Tests"
            bats tests/smoke/*.bats
            ;;
        integration)
            print_header "Running Integration Tests"
            if [[ -d tests/integration ]] && ls tests/integration/*.bats &>/dev/null; then
                bats tests/integration/*.bats
            else
                print_warning "No integration tests found"
            fi
            ;;
        *)
            print_header "Running All Tests"
            bats tests/unit/*.bats tests/smoke/*.bats
            if [[ -d tests/integration ]] && ls tests/integration/*.bats &>/dev/null; then
                bats tests/integration/*.bats
            fi
            ;;
    esac
}

# Main
main() {
    case "${1:-all}" in
        --install|-i)
            install_bats
            ;;
        lint|shellcheck)
            run_shellcheck
            ;;
        syntax)
            run_syntax_check
            ;;
        unit)
            run_bats_tests unit
            ;;
        smoke)
            run_bats_tests smoke
            ;;
        integration)
            run_bats_tests integration
            ;;
        docker)
            run_docker_tests
            ;;
        all)
            run_syntax_check
            echo ""
            run_shellcheck || true
            echo ""
            run_bats_tests all
            ;;
        --help|-h)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  all          Run all tests (default)"
            echo "  unit         Run unit tests only"
            echo "  smoke        Run smoke tests only"
            echo "  integration  Run integration tests only"
            echo "  docker       Run Docker integration tests"
            echo "  lint         Run ShellCheck only"
            echo "  syntax       Run bash syntax check only"
            echo "  --install    Install bats-core"
            echo "  --help       Show this help"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Run '$0 --help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
