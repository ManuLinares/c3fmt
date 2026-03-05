import std;
import c3fmt;

const String ROOT = "test/stdlib/src";

faultdef INVALID_PATH;

struct Results
{
    Atomic{int} formatted;
    Atomic{int} skipped;
}

struct Context
{
    List{String}* paths;
    Atomic{int} next_index;
    Results* results;
}

Context g_ctx;


fn void stability_worker_task(any[] args)
{
    while (true)
    {
        int i = g_ctx.next_index.add(1);
        if (i >= (int)g_ctx.paths.len()) break;

        String path_s = (*g_ctx.paths)[(usz)i];

        @pool_init(mem, 1024 * 1024)
        {
            Path path = path::new(tmem, path_s)!!;
            String input = (String)file::load(tmem, path_s)!!;
            String? formatted = c3fmt::format_string(tmem, input, check_semantic: true);

            if (catch excuse = formatted)
            {
                io::eprintfn("Skipping: %s (%s)", path_s, excuse);
                g_ctx.results.skipped.add(1);
            }
            else
            {
                String? reformatted = c3fmt::format_string(tmem, formatted, check_semantic: true);

                if (catch excuse2 = reformatted)
                {
                    io::eprintfn("Error during second format of %s: %s", path_s, excuse2);
                    unreachable();
                }

                if (formatted != reformatted)
                {
                    io::eprintfn("Stability failure: %s", path_s);
                    unreachable();
                }
                g_ctx.results.formatted.add(1);
            }
        };
    }
}

fn bool? collect_paths(Path path, bool is_dir, any data)
{
    if (!is_dir)
    {
        List{String}* list = (List{String}*)data;
        list.push(path.str_view().copy(mem));
    }
    return false;
}

fn void stability() @test
{
    Path root = path::new(mem, ROOT)!!;
    defer root.free();

    List{String} paths;
    paths.init(mem);
    defer
    {
        foreach (p : paths) p.free(mem);
        paths.free();
    }

    path::traverse(root, &collect_paths, &paths)!!;

    Results results;
    results.formatted.store(0);
    results.skipped.store(0);


    g_ctx.paths = &paths;
    g_ctx.next_index.store(0);
    g_ctx.results = &results;

    usz num_threads = os::num_cpu();
    FixedThreadPool pool;
    pool.init(num_threads, num_threads)!!;
    defer pool.stop_and_destroy();

    for (usz i = 0; i < num_threads; i++)
    {
        pool.push(&stability_worker_task)!!;
    }

    pool.join()!!;

    io::printfn("Stability test result: %d formatted, %d skipped due to syntax errors.", results.formatted.load(), results.skipped.load());
}
