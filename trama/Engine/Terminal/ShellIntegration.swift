import Foundation

public enum ShellIntegration {
    public static func install(at directory: String) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, content) in files {
            let path = directory + "/" + name
            if (try? String(contentsOfFile: path, encoding: .utf8)) != content {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func environment(directory: String, home: String? = nil) -> [String] {
        let current = ProcessInfo.processInfo.environment
        let userDirectory = home ?? current["ZDOTDIR"] ?? current["HOME"] ?? NSHomeDirectory()
        return [
            "ZDOTDIR=\(directory)",
            "TRAMA_ZDOTDIR=\(directory)",
            "TRAMA_USER_ZDOTDIR=\(userDirectory)",
            "TRAMA_SHELL_INTEGRATION=1",
        ]
    }

    private static func forward(_ file: String) -> String {
        """
        if [[ -r $TRAMA_USER_ZDOTDIR/\(file) ]]; then
          ZDOTDIR=$TRAMA_USER_ZDOTDIR
          source $ZDOTDIR/\(file)
          ZDOTDIR=$TRAMA_ZDOTDIR
        fi

        """
    }

    private static let files: [String: String] = [
        ".zshenv": forward(".zshenv") + """
        TRAMA_USER_ZDOTDIR=${TRAMA_USER_ZDOTDIR:-$HOME}
        [[ -z $HISTFILE ]] && HISTFILE=$TRAMA_USER_ZDOTDIR/.zsh_history

        """,
        ".zprofile": forward(".zprofile"),
        ".zshrc": forward(".zshrc") + hooks,
        ".zlogin": forward(".zlogin") + """
        ZDOTDIR=$TRAMA_USER_ZDOTDIR

        """,
    ]

    private static let hooks = """
    if [[ -o interactive && -n $TRAMA_SHELL_INTEGRATION ]]; then
      autoload -Uz add-zsh-hook
      typeset -g __trama_command_ran=0
      __trama_escape() {
        REPLY=${1//\\\\/\\\\\\\\}
        REPLY=${REPLY//$'\\n'/\\\\x0a}
        REPLY=${REPLY//$'\\e'/\\\\x1b}
        REPLY=${REPLY//$'\\a'/\\\\x07}
        REPLY=${REPLY//;/\\\\x3b}
      }
      __trama_preexec() {
        __trama_command_ran=1
        __trama_escape "$1"
        builtin printf '\\e]633;E;%s\\a\\e]133;C\\a' "$REPLY"
      }
      __trama_precmd() {
        local exit_code=$?
        if (( __trama_command_ran )); then
          builtin printf '\\e]133;D;%s\\a' "$exit_code"
          __trama_command_ran=0
        fi
        local dir=${PWD//\\%/%25}
        dir=${dir// /%20}
        builtin printf '\\e]7;file://%s%s\\a\\e]133;A\\a' "$HOST" "$dir"
        [[ $PS1 == *'133;B'* ]] || PS1+=$'%{\\e]133;B\\a%}'
      }
      add-zsh-hook preexec __trama_preexec
      add-zsh-hook precmd __trama_precmd
    fi

    """
}
