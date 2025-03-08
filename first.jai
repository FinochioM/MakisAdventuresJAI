OUTPUT_EXECUTABLE_NAME := "makis_adventure";

#run {
    set_build_options_dc(.{do_output = false});

    log("Compiling farm game...");

    w := compiler_create_workspace("Target workspace");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = OUTPUT_EXECUTABLE_NAME;
    options.output_path = ".";

    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("source/main.jai", w);

    while true {
        message := compiler_wait_for_message();
        if message.kind == {
            case .ERROR;
                exit(1);
            case .COMPLETE;
                break;
        }
    }
    compiler_end_intercept(w);
};

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "String";