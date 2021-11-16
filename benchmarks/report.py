#!/usr/bin/env python3
import sys
import os
from datetime import datetime
import argparse
from definitions import *
import matplotlib.pyplot as plt
import shutil


def caption(exp_setup):
    return "Experimental Results for Realizable Benchmarks.  Benchmarks are grouped by categories introduced in Section \\ref{sec:evaluation}. All times are in seconds. The best time is highlighted in bold font.  A '-' indicates timeout ($>$ 10 min). The ``B'' column indicates if using bounded checking was used to classify a counterexample or validate a lemma. Steps is a sequence of '$\\bullet$' (refinement) and '$\\circ$' (coarsening). Experiments are run on %s." % exp_setup


def caption_unrealizable(exp_setup):
    return "Experimental Results for Unrealizable Benchmarks. All synthesis times are in seconds. The best time is highlighted in bold font.  A '-' indicates timeout ($>$ 10 min). The ``B'' column indicates if using bounded checking was used to classify a counterexample or validate a lemma. Steps is a sequence of '$\\bullet$' (refinement) and '$\\circ$' (coarsening). Experiments are run on %s." % exp_setup


def timefix(x):
    if x in timeout_names:
        return "-"
    else:
        return x


def roundfix(s):
    if s == "None":
        s = "-"
    else:
        s = s[:-1]
    s = s.replace("^", "l")
    s = s.replace("+", "\\bullet")
    s = s.replace(".", "\\circ")
    return s


def unrealizable(s):
    return s.endswith("∅")


def roundcount(s):

    if s.startswith("f"):
        return s[:1]

    if s == "None":
        s = "-"
    else:
        s = s[:-1]
    return str(len(s))


def empty_exp_data(info, realizable=True):
    #        category   benchmark NB time  ref. time  ref.
    if realizable:
        res = f"{info[0]}&{info[1]}& ? & ?   & ?  & ?  & ?  \\\\ %chktex 26\n"
    else:
        res = f"{info[1]}& ? & ?   & ?  & ?  & ?  \\\\ %chktex 26\n"
    return res


def with_exp_data(info, data, data2, realizable=True):
    #    se2gis_result = {
    #                 "time": info[2],
    #                 "delta": info[3],
    #                 "rounds": info[4],
    #                 "N": info[5],
    #                 "B": info[6],
    #                 "verif": info[7],
    #             }
    if data['B'] == "✓":
        req_bounding = "y"
    else:
        req_bounding = "n"

    rounds = f"${roundfix(data['rounds'])}$"
    rounds2 = roundcount(data2['rounds'])

    time1 = timefix(data['time'])
    time2 = timefix(data2['time'])

    if (not data['time'] in timeout_names) and (data2['time'] in timeout_names or data2['time'] > data['time']):
        time1 = "{\\bf" + data['time'] + "}"
    elif not data2['time'] in timeout_names:
        time2 = "{\\bf" + data2['time'] + "}"

    if realizable:
        res = f"{info[0]} & {info[1]} & { req_bounding } & {time1} & {rounds} & {time2}  & {rounds2}  \\\\ \n"
    else:
        res = f"{info[1]} & { req_bounding } & {time1} & {rounds} & {time2}  & {rounds2}  \\\\ \n"
    return res


def make_tex_table(exp_setup, data, output_file_name):
    tex = open(output_file_name, 'w+')
    tex.write("%s ====================================\n" % '%')
    tex.write(
        "%s This table has been automatically produced by the tool on %s.\n" %
        ('%', str(datetime.now())))
    tex.write("%s ====================================\n" % '%')
    # open table
    tex.write("\t{\n")
    tex.write("\t\t\\begin{longtable}[h]{|c|c|c|c|c||c|c|}\n")
    tex.write("\t\t\t\\hline\n")
    tex.write(
        "\t\t\t \multirow{2}{*}{Class} &\
                \multirow{2}{*}{Benchmark} & \
                \multirow{2}{*}{B?} & \
                \multicolumn{2}{c||}{\\tool} & \
                \multicolumn{2}{c|}{Baseline}\\\\ \n")
    tex.write("\t\t\t\\cline{4-7}\n")
    tex.write(
        "\t\t\t &   & & time & steps & time & \\#'r' \\\\ \n")
    speedups = []
    for benchmark_class, benchmarks in show_benchmarks.items():
        tex.write("\t\t\t\\hline\n")
        for benchmark, benchmark_info in benchmarks.items():
            benchmark_file = benchmark_class + "/" + benchmark
            experimental_data = data.get(benchmark_file)
            if experimental_data is None:
                tex.write(empty_exp_data(benchmark_info))
            else:
                tex.write(with_exp_data(benchmark_info,
                          experimental_data[0], experimental_data[1]))

    tex.write("\t\t\t\\hline\n")
    tex.write("\t\caption{%s}\label{table:experiments}\n" % caption(exp_setup))
    tex.write("\t\t\end{longtable}\n")
    tex.write("\t}\n")
    tex.close()


def make_tex_unrealizables_table(exp_setup, data, output_file_name):
    tex = open(output_file_name, 'w+')
    tex.write("%s ====================================\n" % '%')
    tex.write(
        "%s This table has been automatically produced by the tool on %s.\n" %
        ('%', str(datetime.now())))
    tex.write("%s ====================================\n" % '%')
    # open table
    tex.write("\t{\n")
    tex.write("\t\t\\begin{longtable}[h]{|c|c|c|c||c|c|}\n")
    tex.write("\t\t\t\\hline\n")
    tex.write(
        "\t\t\t\multirow{2}{*}{Benchmark} & \
                \multirow{2}{*}{B?} & \
                \multicolumn{2}{c||}{\\tool} & \
                \multicolumn{2}{c|}{Baseline}\\\\ \n")
    tex.write("\t\t\t\\cline{3-6}\n")
    tex.write(
        "\t\t\t & & time & steps & time & \\#'r' \\\\ \n")
    speedups = []
    for benchmark_class, benchmarks in unrealizable_show_set.items():
        tex.write("\t\t\t\\hline\n")
        for benchmark, benchmark_info in benchmarks.items():
            benchmark_file = benchmark_class + "/" + benchmark
            experimental_data = data.get(benchmark_file)
            if experimental_data is None:
                tex.write(empty_exp_data(benchmark_info, False))
            else:
                tex.write(with_exp_data(benchmark_info,
                          experimental_data[0], experimental_data[1], False))

    tex.write("\t\t\t\\hline\n")
    tex.write(
        "\t\caption{%s}\label{table:unrealizable-experiments}\n" % caption_unrealizable(exp_setup))
    tex.write("\t\t\end{longtable}\n")
    tex.write("\t}\n")
    tex.close()


def quantile_plot(quantile_file, segis_series, se2gis_series):
    fig, ax = plt.subplots(figsize=(6, 4))
    s1 = [x for x in sorted(
        se2gis_series) if x < timeout_value]
    s2 = [x for x in sorted(
        segis_series) if x < timeout_value]
    ax.plot(s1, color="purple", label="SE²GIS",
            linestyle="solid", linewidth=1.5)
    ax.plot(s2, color="darkorange", label="SEGIS (baseline)",
            linestyle="solid", linewidth=1.5)
    ax.set_xlabel("Number of benchmarks solved", fontsize=plot_fontsize)
    ax.set_ylabel("Time", fontsize=plot_fontsize)
    ax.legend(fontsize=plot_fontsize)
    fig.savefig(quantile_file, bbox_inches='tight')


def save_scatter_plot(scatter_file, segis_series, se2gis_series,
                      segis_unrealizable_series, se2gis_unrealizable_series, timeouts=False):

    if timeouts:
        fig, ax = plt.subplots(figsize=(4, 4))
        ax.plot(segis_series, se2gis_series, "x", color="firebrick")
        ax.plot(segis_unrealizable_series,
                se2gis_unrealizable_series, "x", color="blue")
        ax.set_xscale("log")
        ax.set_yscale("log")
        all_points = segis_series + se2gis_series + \
            se2gis_unrealizable_series + segis_unrealizable_series
        ax_min = 0.5*min(all_points)
        ax_max = 5*max(all_points)
        ax.set(xlim=(ax_min, ax_max),
               ylim=(ax_min, ax_max))
        ax.set_xlabel("Synthesis time using SEGIS baseline (log)",
                      fontsize=plot_fontsize)
        ax.set_ylabel("Synthesis time using SE²GIS (log)",
                      fontsize=plot_fontsize)

        ax.plot([0, 1], [0, 1], color="black",
                linestyle="dotted", transform=ax.transAxes)
        ax.set_aspect('equal')
        fig.savefig(scatter_file, bbox_inches='tight')
    else:
        no_timeouts = list(filter(lambda d: d[0] != timeout_value and d[1] != timeout_value, zip(
            segis_series, se2gis_series)))
        no_timeouts_unr = list(filter(lambda d: d[0] != timeout_value and d[1] != timeout_value, zip(
            segis_unrealizable_series, se2gis_unrealizable_series)))
        segis_series_no_timeout = [d[0] for d in no_timeouts]
        se2gis_series_no_timeout = [d[1] for d in no_timeouts]
        segis_unr_series_no_timeout = [d[0] for d in no_timeouts_unr]
        se2gis_unr_series_no_timeout = [d[1] for d in no_timeouts_unr]
        fig, ax = plt.subplots(figsize=(4, 4))
        ax.plot(segis_series_no_timeout,
                se2gis_series_no_timeout, "x", color="firebrick")
        ax.plot(segis_unr_series_no_timeout,
                se2gis_unr_series_no_timeout, "x", color="blue")
        all_points_notimeout = segis_series_no_timeout + se2gis_series_no_timeout + \
            se2gis_unr_series_no_timeout + segis_unr_series_no_timeout
        ax_min = 0.5*min(all_points_notimeout)
        ax_max = 1.5*max(all_points_notimeout)
        ax.set(xlim=(ax_min, ax_max),
               ylim=(ax_min, ax_max))
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.set_xlabel("Synthesis time using SEGIS (log)",
                      fontsize=plot_fontsize)
        ax.set_ylabel("Synthesis time using SE²GIS (log)",
                      fontsize=plot_fontsize)
        diag_max = int(min(max(segis_series_no_timeout),
                           max(se2gis_series_no_timeout)))
        ax.plot([0, timeout_value], [0, timeout_value], color="grey",
                linestyle="dotted")

        ax.set_aspect('equal')
        fig.savefig(scatter_file, bbox_inches='tight')


def make_table_5(input_file, output_file):
    print("============== SUMMARY ================")
    print("Summary of relative improvement of Synduce over baseline.")
    print("improvement = baseline synt. time / Synduce synt. time")
    print("∞ means baseline timed out, but Synduce did not")
    print("-∞ means Synduce timed out, but baseline did not,")
    print("! means both timed out.")
    print("---------------------------------------------")
    # Table 5 line format
    # benchmark, se2gis_algo_name, time, delta, rounds, N, B, verif, segis_algo_name, time, delta, rounds, N, B ,verif
    #     0            1            2      3       4    5  6    7         8            9     10     11     12 13 14

    segis_timeouts = 0
    se2gis_timeouts = 0
    speedups = 0
    print("%54s, %7s,  %5s : %5s" %
          ("Benchmark", "SE2GIS", " SEGIS", "Speedup"))

    exp_setup = experimental_setup_2
    input_name = input_file.split(".")[0]
    quantile_file = input_name + "_quantile.pdf"
    scatter_file = input_name + "_scatter.pdf"
    scatter_no_timeouts_file = input_name + "_no_timeouts_scatter.pdf"
    tex_table = input_name + "_table.tex"
    tex_table2 = input_name + "_table_unrealizable.tex"

    table = {}

    se2gis_series = []
    segis_series = []
    se2gis_unrealizable_series = []
    segis_unrealizable_series = []
    segis0_series = []
    segis0_unrealizable_series = []

    with open(input_file, 'r') as csv:
        for line in csv.readlines():
            if line.startswith("SETUP:"):
                exp_setup = line[5:]
                continue
            info = line.split(",")
            if len(info) >= 15:
                benchmark = info[0].split(".")[0]
                se2gis_result = {
                    "time": info[2],
                    "delta": info[3],
                    "rounds": info[4],
                    "N": info[5],
                    "B": info[6],
                    "verif": info[7],
                }
                segis_result = {
                    "time": info[9],
                    "delta": info[10],
                    "rounds": info[11],
                    "N": info[12],
                    "B": info[13],
                    "verif": info[14],
                }

                # We may have data for SEGIS base
                segis0_data = False
                if len(info) == 21:
                    segis0_data = True
                    segis0_result = {
                        "time": info[15],
                        "delta": info[16],
                        "rounds": info[17],
                        "N": info[18],
                        "B": info[19],
                        "verif": info[20],
                    }
                    c = segis0_result['time']

                table[benchmark] = (se2gis_result, segis_result)

                a = se2gis_result['time']
                b = segis_result['time']

                if floti(a) < floti(b):
                    speedups += 1

                if floti(a) == timeout_value:
                    se2gis_timeouts += 1

                if floti(b) == timeout_value:
                    segis_timeouts += 1

                if unrealizable(info[4]):
                    se2gis_unrealizable_series.append(floti(a))
                    segis_unrealizable_series.append(floti(b))
                    if segis0_data:
                        segis0_unrealizable_series.append(floti(b))
                else:
                    se2gis_series.append(floti(a))
                    segis_series.append(floti(b))
                    if segis0_data:
                        segis0_series.append(floti(b))

                print("%54s, %7s, %7s : %5s" %
                      (benchmark, a, b, speedup(a, b)))

    # Plot a scatter plot with a diagonal line
    save_scatter_plot(scatter_file, segis_series, se2gis_series,
                      segis_unrealizable_series, se2gis_unrealizable_series, timeouts=True)

    # Plot a scatter plot with a diagonal line, omitting timeouts
    save_scatter_plot(scatter_no_timeouts_file, segis_series, se2gis_series,
                      segis_unrealizable_series, se2gis_unrealizable_series)

    segis_series = segis_series + segis_unrealizable_series
    se2gis_series = se2gis_series + se2gis_unrealizable_series
    # Plot a quantile plot
    quantile_plot(quantile_file, segis_series, se2gis_series)
    # Output a tex table for  realizable benchmarks
    make_tex_table(exp_setup, table, tex_table)
    # Output a tex table for unrealizable benchmarks
    make_tex_unrealizables_table(exp_setup, table, tex_table2)

    print(f"Number of benchmarks: {len(segis_series)}")
    print(f"{segis_timeouts} timeouts for SEGIS, {se2gis_timeouts} timeouts for SE2GIS.")
    print(f"SE2GIS is faster on {speedups} benchmarks.")
    print(f"Tex table    : { tex_table}  ")
    print(f"Quantile plot: {quantile_file}")
    print(f"Scatter plot : {scatter_file}")
    print(f"Scatter plot (omitting timeouts) : {scatter_no_timeouts_file}")
    return {
        "quantile": quantile_file,
        "scatter": scatter_file,
        "scatter_no_timeouts": scatter_no_timeouts_file,
        "table": tex_table,
        "table2": tex_table2
    }


def select_last_known_experimental_data(table_no):
    candidates = []
    for root, dirs, files in os.walk("benchmarks/data/exp"):
        for file in files:
            comps = file.split("_")
            if len(comps) > 1 and file.endswith(".csv"):
                try:
                    date_generated = datetime.strptime(
                        comps[1].strip(), timestamp_definition)
                    file_table_no = comps[2].split(".")[0][-1]
                    if table_no == int(file_table_no):
                        candidates.append((date_generated, file))
                except ValueError as e:
                    pass

    candidates = sorted(candidates, key=lambda x: x[0], reverse=True)
    if len(candidates) > 0:
        return f"benchmarks/data/exp/{candidates[0][1]}"
    else:
        return None


if __name__ == "__main__":
    aparser = argparse.ArgumentParser()
    aparser.add_argument(
        "-i", "--input", help="The input file produced by running test.py", type=str, default=None)
    aparser.add_argument(
        "-o", "--output", help="The output text file for the table.", type=str, default="benchmarks/table.txt")
    aparser.add_argument(
        "-t", "--table", help="Table number that the script must generate.", type=int, choices=[0, 1, 2, 3, 4, 5], default=0)
    aparser.add_argument(
        "-c", "--csv", help="The output csv file for results.", type=str, default="benchmarks/constraints_results.csv")
    aparser.add_argument(
        "-e", "--explain", help="Explain where the benchmarks are stored.", action="store_true")
    aparser.add_argument(
        "-y", "--copy", help="Copy figures to $SYND_LOCAL_COPY/figures and $SYND_LOCAL_COPY/tables.", action="store_true"
    )

    args = aparser.parse_args()

    if args.explain:
        explain()
        exit()

    input_file = args.input
    output_file = args.csv
    table_no = args.table
    tex_out = args.output

    if (table_no is None) or table_no < 0 or table_no > 5:
        print("Please provide a table number between 0 and 5.")
        exit()

    if not input_file:
        input_file = select_last_known_experimental_data(table_no)
        print(f"Input file selected: {input_file}")

    if table_no == 5 or table_no == 0 and input_file:
        filenames = make_table_5(input_file, output_file)

        if args.copy:
            LOCAL_COPY = os.getenv('SYND_LOCAL_COPY')
            if LOCAL_COPY is not None:
                shutil.copyfile(filenames['table'], os.path.join(
                    LOCAL_COPY, "tables/table.tex"))
                shutil.copyfile(filenames['table2'], os.path.join(
                    LOCAL_COPY, "tables/table_unrealizable.tex"))
                shutil.copyfile(filenames['quantile'], os.path.join(
                    LOCAL_COPY, "figures/quantile.pdf"))
                shutil.copyfile(filenames['scatter'], os.path.join(
                    LOCAL_COPY, "figures/scatter.pdf"))
                shutil.copyfile(filenames['scatter_no_timeouts'], os.path.join(
                    LOCAL_COPY, "figures/no_timeouts_scatter.pdf"))
