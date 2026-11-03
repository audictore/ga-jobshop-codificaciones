// Actividad 05 - Algoritmo genetico aplicado a la programacion de un taller de maquinado (Job-Shop)
// Compara tres codificaciones del cromosoma: binaria, permutacion con repeticion (entera) y llaves aleatorias (real).
// Compilacion: csc /out:GaJobShop.exe GaJobShop.cs /r:System.Drawing.dll     (C# 5, .NET Framework 4.x)
// Uso:         GaJobShop.exe <carpeta_de_salida>
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace GaJobShop
{
    // ------------------------------------------------------------------ instancia (datos sinteticos)
    class Instance
    {
        public int J, M, N;
        public string[] MachineNames = { "Corte", "Torno", "Fresado", "Taladrado", "Rectificado", "Inspección" };
        int[] minT = { 10, 20, 20, 15, 15, 5 };
        int[] maxT = { 30, 60, 60, 50, 55, 20 };
        public int[] Off, Len, OpJob, OpPos, OpMach, OpTime;
        public int LowerBound, MaxMachLoad, MaxJobLen;

        public Instance(int jobs, int seed)
        {
            J = jobs; M = 6;
            Random r = new Random(seed);
            List<int>[] route = new List<int>[J];
            List<int>[] time = new List<int>[J];
            for (int j = 0; j < J; j++)
            {
                // Corte siempre primero, Inspeccion siempre al final, 3..4 maquinas intermedias en orden aleatorio
                List<int> mid = new List<int> { 1, 2, 3, 4 };
                for (int i = mid.Count - 1; i > 0; i--) { int k = r.Next(i + 1); int t = mid[i]; mid[i] = mid[k]; mid[k] = t; }
                int take = 3 + r.Next(2);
                route[j] = new List<int>(); route[j].Add(0);
                for (int i = 0; i < take; i++) route[j].Add(mid[i]);
                route[j].Add(5);
                time[j] = new List<int>();
                foreach (int m in route[j]) time[j].Add(minT[m] + r.Next(maxT[m] - minT[m] + 1));
            }
            Off = new int[J]; Len = new int[J];
            N = 0;
            for (int j = 0; j < J; j++) { Off[j] = N; Len[j] = route[j].Count; N += Len[j]; }
            OpJob = new int[N]; OpPos = new int[N]; OpMach = new int[N]; OpTime = new int[N];
            int[] load = new int[M];
            for (int j = 0; j < J; j++)
            {
                int len = 0;
                for (int k = 0; k < Len[j]; k++)
                {
                    int o = Off[j] + k;
                    OpJob[o] = j; OpPos[o] = k; OpMach[o] = route[j][k]; OpTime[o] = time[j][k];
                    load[OpMach[o]] += OpTime[o]; len += OpTime[o];
                }
                MaxJobLen = Math.Max(MaxJobLen, len);
            }
            MaxMachLoad = load.Max();
            LowerBound = Math.Max(MaxMachLoad, MaxJobLen);
        }
    }

    // ------------------------------------------------------------------ decodificador (genotipo -> fenotipo)
    // Recibe un vector de prioridades por operacion (menor valor = mayor prioridad) y construye un
    // calendario ACTIVO con el algoritmo de Giffler-Thompson. El mismo decodificador sirve a las 3 codificaciones.
    class Decoder
    {
        Instance I; int[] next, jr, mr;
        public int[] Start; public int[] Finish;
        public Decoder(Instance ins) { I = ins; next = new int[ins.J]; jr = new int[ins.J]; mr = new int[ins.M]; Start = new int[ins.N]; Finish = new int[ins.N]; }

        public int Decode(double[] pr)
        {
            Array.Clear(next, 0, next.Length); Array.Clear(jr, 0, jr.Length); Array.Clear(mr, 0, mr.Length);
            int cmax = 0;
            for (int step = 0; step < I.N; step++)
            {
                int bestEct = int.MaxValue, bestM = -1;
                for (int j = 0; j < I.J; j++)
                {
                    if (next[j] >= I.Len[j]) continue;
                    int o = I.Off[j] + next[j], m = I.OpMach[o];
                    int ect = Math.Max(jr[j], mr[m]) + I.OpTime[o];
                    if (ect < bestEct) { bestEct = ect; bestM = m; }
                }
                int chosen = -1; double bp = double.MaxValue;
                for (int j = 0; j < I.J; j++)
                {
                    if (next[j] >= I.Len[j]) continue;
                    int o = I.Off[j] + next[j];
                    if (I.OpMach[o] != bestM) continue;
                    if (Math.Max(jr[j], mr[bestM]) < bestEct && pr[o] < bp) { bp = pr[o]; chosen = j; }
                }
                int op = I.Off[chosen] + next[chosen];
                int st = Math.Max(jr[chosen], mr[bestM]), fin = st + I.OpTime[op];
                Start[op] = st; Finish[op] = fin; jr[chosen] = fin; mr[bestM] = fin; next[chosen]++;
                if (fin > cmax) cmax = fin;
            }
            return cmax;
        }
    }

    // ------------------------------------------------------------------ codificaciones
    abstract class Codec
    {
        public string Name;
        public abstract object NewRandom(Random r);
        public abstract void ToPriorities(object g, double[] pr);
        public abstract void Cross(object a, object b, Random r, out object c1, out object c2);
        public abstract void Mutate(object g, Random r);
        public abstract object Clone(object g);
    }

    // 1) Binaria: cada operacion tiene 8 bits; el entero (0..255) es su prioridad.
    class BinaryCodec : Codec
    {
        int N, B = 8, L; double pm;
        public BinaryCodec(Instance ins) { Name = "Binaria"; N = ins.N; L = N * B; pm = 2.0 / L; }
        public override object NewRandom(Random r) { byte[] g = new byte[L]; for (int i = 0; i < L; i++) g[i] = (byte)r.Next(2); return g; }
        public override void ToPriorities(object o, double[] pr)
        {
            byte[] g = (byte[])o;
            for (int op = 0; op < N; op++) { int v = 0; for (int b = 0; b < B; b++) v = (v << 1) | g[op * B + b]; pr[op] = v + op * 1e-6; }
        }
        public override void Cross(object a, object b, Random r, out object c1, out object c2)
        {
            byte[] pa = (byte[])a, pb = (byte[])b, x = (byte[])pa.Clone(), y = (byte[])pb.Clone();
            int p = r.Next(L), q = r.Next(L); if (p > q) { int t = p; p = q; q = t; }
            for (int i = p; i <= q; i++) { x[i] = pb[i]; y[i] = pa[i]; }   // cruza de dos puntos
            c1 = x; c2 = y;
        }
        public override void Mutate(object o, Random r) { byte[] g = (byte[])o; for (int i = 0; i < L; i++) if (r.NextDouble() < pm) g[i] ^= 1; }
        public override object Clone(object g) { return ((byte[])g).Clone(); }
    }

    // 2) Permutacion con repeticion (entera): el job j aparece tantas veces como operaciones tiene.
    //    La posicion de cada aparicion en el cromosoma es la prioridad de esa operacion.
    class PermCodec : Codec
    {
        Instance I; double pm = 0.30;
        public PermCodec(Instance ins) { Name = "Permutación con repetición"; I = ins; }
        public override object NewRandom(Random r)
        {
            int[] g = new int[I.N]; int k = 0;
            for (int j = 0; j < I.J; j++) for (int i = 0; i < I.Len[j]; i++) g[k++] = j;
            for (int i = g.Length - 1; i > 0; i--) { int s = r.Next(i + 1); int t = g[i]; g[i] = g[s]; g[s] = t; }
            return g;
        }
        public override void ToPriorities(object o, double[] pr)
        {
            int[] g = (int[])o; int[] cnt = new int[I.J];
            for (int pos = 0; pos < g.Length; pos++) { int j = g[pos]; pr[I.Off[j] + cnt[j]++] = pos; }
        }
        public override void Cross(object a, object b, Random r, out object c1, out object c2)
        {
            int[] pa = (int[])a, pb = (int[])b;
            bool[] inSet = new bool[I.J]; int sz = 0;
            for (int j = 0; j < I.J; j++) { inSet[j] = r.Next(2) == 0; if (inSet[j]) sz++; }
            if (sz == 0) inSet[r.Next(I.J)] = true;
            c1 = Pox(pa, pb, inSet); c2 = Pox(pb, pa, inSet);          // POX: Precedence Operation Crossover
        }
        int[] Pox(int[] keep, int[] fill, bool[] inSet)
        {
            int n = keep.Length; int[] c = new int[n]; bool[] fixedPos = new bool[n];
            for (int i = 0; i < n; i++) if (inSet[keep[i]]) { c[i] = keep[i]; fixedPos[i] = true; }
            int k = 0;
            for (int i = 0; i < n; i++)
            {
                if (fixedPos[i]) continue;
                while (inSet[fill[k]]) k++;
                c[i] = fill[k++];
            }
            return c;
        }
        public override void Mutate(object o, Random r)
        {
            if (r.NextDouble() >= pm) return;
            int[] g = (int[])o; int p = r.Next(g.Length), q = r.Next(g.Length);
            int t = g[p]; g[p] = g[q]; g[q] = t;                       // mutacion por intercambio
        }
        public override object Clone(object g) { return ((int[])g).Clone(); }
    }

    // 3) Real: llaves aleatorias en [0,1), una por operacion; la llave es la prioridad.
    class KeysCodec : Codec
    {
        int N; double pm, sigma = 0.15;
        public KeysCodec(Instance ins) { Name = "Llaves aleatorias (real)"; N = ins.N; pm = 2.0 / N; }
        public override object NewRandom(Random r) { double[] g = new double[N]; for (int i = 0; i < N; i++) g[i] = r.NextDouble(); return g; }
        public override void ToPriorities(object g, double[] pr) { Array.Copy((double[])g, pr, N); }
        public override void Cross(object a, object b, Random r, out object c1, out object c2)
        {
            double[] pa = (double[])a, pb = (double[])b, x = new double[N], y = new double[N];
            for (int i = 0; i < N; i++) { if (r.Next(2) == 0) { x[i] = pa[i]; y[i] = pb[i]; } else { x[i] = pb[i]; y[i] = pa[i]; } }   // cruza uniforme
            c1 = x; c2 = y;
        }
        public override void Mutate(object o, Random r)
        {
            double[] g = (double[])o;
            for (int i = 0; i < N; i++)
                if (r.NextDouble() < pm)
                {
                    double u1 = 1 - r.NextDouble(), u2 = r.NextDouble();
                    double z = Math.Sqrt(-2 * Math.Log(u1)) * Math.Cos(2 * Math.PI * u2);
                    g[i] = Math.Min(0.999999, Math.Max(0, g[i] + sigma * z));   // mutacion gaussiana
                }
        }
        public override object Clone(object g) { return ((double[])g).Clone(); }
    }

    // ------------------------------------------------------------------ algoritmo genetico
    class RunResult { public int Best; public double[] BestPerGen; public int GenFound; public long Ms; public double[] BestPriorities; public int Evals; }

    static class Ga
    {
        public const int Pop = 100, Gens = 300, Elite = 2, TourK = 3;
        public const double Pc = 0.90;

        public static int EvalsPerRun() { return Pop + Gens * (Pop - Elite); }

        public static RunResult Run(Instance ins, Codec codec, int seed)
        {
            Stopwatch sw = Stopwatch.StartNew();
            Random r = new Random(seed);
            Decoder dec = new Decoder(ins);
            double[] pr = new double[ins.N];
            object[] pop = new object[Pop]; int[] fit = new int[Pop];
            RunResult res = new RunResult { BestPerGen = new double[Gens + 1] };
            int best = int.MaxValue; double[] bestPr = null; int evals = 0;
            // etapa 2 y 3: poblacion inicial y evaluacion
            for (int i = 0; i < Pop; i++) { pop[i] = codec.NewRandom(r); fit[i] = Eval(codec, dec, pop[i], pr); evals++; Track(fit[i], pr, ref best, ref bestPr, res, 0); }
            res.BestPerGen[0] = best;
            for (int g = 1; g <= Gens; g++)
            {
                int[] idx = Enumerable.Range(0, Pop).OrderBy(i => fit[i]).ToArray();
                object[] np = new object[Pop]; int[] nf = new int[Pop]; int n = 0;
                for (int e = 0; e < Elite; e++) { np[n] = codec.Clone(pop[idx[e]]); nf[n] = fit[idx[e]]; n++; }     // etapa 7: reemplazo con elitismo
                while (n < Pop)
                {
                    object p1 = pop[Tournament(fit, r)], p2 = pop[Tournament(fit, r)];       // etapa 4: seleccion por torneo
                    object c1, c2;
                    if (r.NextDouble() < Pc) codec.Cross(p1, p2, r, out c1, out c2);          // etapa 5: cruza
                    else { c1 = codec.Clone(p1); c2 = codec.Clone(p2); }
                    codec.Mutate(c1, r); codec.Mutate(c2, r);                                  // etapa 6: mutacion
                    np[n] = c1; nf[n] = Eval(codec, dec, c1, pr); evals++; Track(nf[n], pr, ref best, ref bestPr, res, g); n++;
                    if (n < Pop) { np[n] = c2; nf[n] = Eval(codec, dec, c2, pr); evals++; Track(nf[n], pr, ref best, ref bestPr, res, g); n++; }
                }
                pop = np; fit = nf;
                res.BestPerGen[g] = best;
            }
            res.Best = best; res.BestPriorities = bestPr; res.Evals = evals; res.Ms = sw.ElapsedMilliseconds;
            return res;
        }

        static int Eval(Codec c, Decoder d, object g, double[] pr) { c.ToPriorities(g, pr); return d.Decode(pr); }

        static void Track(int f, double[] pr, ref int best, ref double[] bestPr, RunResult res, int gen)
        {
            if (f < best) { best = f; bestPr = (double[])pr.Clone(); res.GenFound = gen; }
        }

        static int Tournament(int[] fit, Random r)
        {
            int w = r.Next(fit.Length);
            for (int i = 1; i < TourK; i++) { int c = r.Next(fit.Length); if (fit[c] < fit[w]) w = c; }
            return w;
        }

        // Linea base: busqueda aleatoria con el mismo numero de evaluaciones
        public static RunResult RandomSearch(Instance ins, int seed)
        {
            Stopwatch sw = Stopwatch.StartNew();
            Random r = new Random(seed); Decoder dec = new Decoder(ins);
            double[] pr = new double[ins.N]; int best = int.MaxValue; double[] bestPr = null;
            int total = EvalsPerRun();
            RunResult res = new RunResult { BestPerGen = new double[Gens + 1] };
            int perGen = total / (Gens + 1), done = 0;
            for (int e = 0; e < total; e++)
            {
                for (int i = 0; i < ins.N; i++) pr[i] = r.NextDouble();
                int f = dec.Decode(pr);
                if (f < best) { best = f; bestPr = (double[])pr.Clone(); res.GenFound = Math.Min(Gens, e / perGen); }
                done++;
                int g = Math.Min(Gens, e / perGen);
                res.BestPerGen[g] = best;
            }
            for (int g = 1; g <= Gens; g++) if (res.BestPerGen[g] == 0) res.BestPerGen[g] = res.BestPerGen[g - 1];
            res.Best = best; res.BestPriorities = bestPr; res.Evals = done; res.Ms = sw.ElapsedMilliseconds;
            return res;
        }
    }

    // ------------------------------------------------------------------ estadistica y graficas
    static class Stats
    {
        public static double Mean(double[] v) { return v.Average(); }
        public static double Std(double[] v) { double m = v.Average(); return Math.Sqrt(v.Sum(x => (x - m) * (x - m)) / (v.Length - 1)); }
        public static double Quantile(double[] v, double q)
        {
            double[] s = v.OrderBy(x => x).ToArray(); double pos = q * (s.Length - 1); int lo = (int)Math.Floor(pos), hi = (int)Math.Ceiling(pos);
            return s[lo] + (s[hi] - s[lo]) * (pos - lo);
        }
        static double Erfc(double x)
        {
            double z = Math.Abs(x), t = 1 / (1 + 0.5 * z);
            double r = t * Math.Exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
            return x >= 0 ? r : 2 - r;
        }
        // Prueba U de Mann-Whitney (aprox. normal con correccion por empates). Devuelve z y p bilateral.
        public static void MannWhitney(double[] a, double[] b, out double z, out double p)
        {
            int n1 = a.Length, n2 = b.Length, n = n1 + n2;
            var all = a.Select(x => new { v = x, g = 0 }).Concat(b.Select(x => new { v = x, g = 1 })).OrderBy(x => x.v).ToArray();
            double[] rank = new double[n]; double tie = 0;
            for (int i = 0; i < n;)
            {
                int j = i; while (j + 1 < n && all[j + 1].v == all[i].v) j++;
                double rk = (i + j) / 2.0 + 1; for (int k = i; k <= j; k++) rank[k] = rk;
                double t = j - i + 1; tie += t * t * t - t; i = j + 1;
            }
            double r1 = 0; for (int i = 0; i < n; i++) if (all[i].g == 0) r1 += rank[i];
            double u1 = r1 - n1 * (n1 + 1) / 2.0, mu = n1 * n2 / 2.0;
            double sd = Math.Sqrt(n1 * n2 / 12.0 * ((n + 1) - tie / ((double)n * (n - 1))));
            z = sd == 0 ? 0 : (u1 - mu) / sd; p = Erfc(Math.Abs(z) / Math.Sqrt(2));
        }
    }

    static class Charts
    {
        public static Color[] Pal = { Color.FromArgb(31, 119, 180), Color.FromArgb(214, 39, 40), Color.FromArgb(44, 160, 44), Color.FromArgb(120, 120, 120) };

        static Graphics Begin(Bitmap bmp)
        {
            Graphics g = Graphics.FromImage(bmp); g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.White); return g;
        }

        public static void Convergence(string path, string[] names, double[][] meanCurves, double lb)
        {
            int W = 1000, H = 600, L = 100, R = 25, T = 65, B = 95;
            Bitmap bmp = new Bitmap(W, H); Graphics g = Begin(bmp);
            double ymin = double.MaxValue, ymax = 0;
            foreach (double[] c in meanCurves) { ymin = Math.Min(ymin, c.Min()); ymax = Math.Max(ymax, c.Max()); }
            ymin = Math.Floor((Math.Min(ymin, lb) - 10) / 10) * 10; ymax = Math.Ceiling((ymax + 45) / 10) * 10;
            int gens = meanCurves[0].Length - 1;
            Func<double, float> X = x => (float)(L + (W - L - R) * x / gens);
            Func<double, float> Y = y => (float)(T + (H - T - B) * (ymax - y) / (ymax - ymin));
            Font f = new Font("Arial", 17), fb = new Font("Arial", 21, FontStyle.Bold);
            g.DrawString("Convergencia: makespan promedio del mejor individuo", fb, Brushes.Black, L - 40, 14);
            Pen grid = new Pen(Color.FromArgb(225, 225, 225), 1);
            double step = (ymax - ymin) > 150 ? 50 : 20;
            for (double y = ymin; y <= ymax + 0.1; y += step) { g.DrawLine(grid, L, Y(y), W - R, Y(y)); g.DrawString(y.ToString("0"), f, Brushes.Black, L - 52, Y(y) - 12); }
            for (int x = 0; x <= gens; x += 50) { g.DrawLine(grid, X(x), T, X(x), H - B); g.DrawString(x.ToString(), f, Brushes.Black, X(x) - 14, H - B + 6); }
            g.DrawRectangle(Pens.Black, L, T, W - L - R, H - T - B);
            Pen lbPen = new Pen(Color.Black, 2) { DashStyle = DashStyle.Dash };
            g.DrawLine(lbPen, L, Y(lb), W - R, Y(lb));
            g.DrawString("Cota inferior = " + lb.ToString("0"), f, Brushes.Black, W - R - 215, Y(lb) - 26);
            for (int k = 0; k < meanCurves.Length; k++)
            {
                Pen p = new Pen(Pal[k], 3f); PointF[] pts = new PointF[gens + 1];
                for (int i = 0; i <= gens; i++) pts[i] = new PointF(X(i), Y(meanCurves[k][i]));
                g.DrawLines(p, pts);
            }
            g.DrawString("Generación", f, Brushes.Black, (W + L) / 2 - 45, H - B + 38);
            g.TranslateTransform(8, (H + T) / 2 + 60); g.RotateTransform(-90); g.DrawString("Makespan (min)", f, Brushes.Black, 0, 0); g.ResetTransform();
            int lx = W - R - 370, ly = T + 14;
            g.FillRectangle(Brushes.White, lx - 10, ly - 8, 365, 32 * names.Length + 10); g.DrawRectangle(Pens.Gray, lx - 10, ly - 8, 365, 32 * names.Length + 10);
            for (int k = 0; k < names.Length; k++)
            { g.DrawLine(new Pen(Pal[k], 4), lx, ly + 32 * k + 12, lx + 40, ly + 32 * k + 12); g.DrawString(names[k], f, Brushes.Black, lx + 50, ly + 32 * k); }
            bmp.Save(path, ImageFormat.Png); g.Dispose(); bmp.Dispose();
        }

        public static void Boxplot(string path, string[] names, double[][] data, double lb)
        {
            int W = 1000, H = 620, L = 100, R = 25, T = 65, B = 115;
            Bitmap bmp = new Bitmap(W, H); Graphics g = Begin(bmp);
            double ymin = Math.Floor((Math.Min(data.Min(d => d.Min()), lb) - 10) / 10) * 10, ymax = Math.Ceiling((data.Max(d => d.Max()) + 10) / 10) * 10;
            Func<double, float> Y = y => (float)(T + (H - T - B) * (ymax - y) / (ymax - ymin));
            Font f = new Font("Arial", 17), fb = new Font("Arial", 21, FontStyle.Bold);
            g.DrawString("Makespan final por método (30 corridas)", fb, Brushes.Black, L - 40, 14);
            Pen grid = new Pen(Color.FromArgb(225, 225, 225), 1);
            double step = (ymax - ymin) > 150 ? 50 : 20;
            for (double y = ymin; y <= ymax + 0.1; y += step) { g.DrawLine(grid, L, Y(y), W - R, Y(y)); g.DrawString(y.ToString("0"), f, Brushes.Black, L - 52, Y(y) - 12); }
            g.DrawRectangle(Pens.Black, L, T, W - L - R, H - T - B);
            Pen lbPen = new Pen(Color.Black, 2) { DashStyle = DashStyle.Dash };
            g.DrawLine(lbPen, L, Y(lb), W - R, Y(lb)); g.DrawString("Cota inferior = " + lb.ToString("0"), f, Brushes.Black, W - R - 215, Y(lb) - 26);
            int n = data.Length; float slot = (W - L - R) / (float)n, bw = slot * 0.35f;
            for (int k = 0; k < n; k++)
            {
                float cx = L + slot * (k + 0.5f);
                double mn = data[k].Min(), q1 = Stats.Quantile(data[k], .25), md = Stats.Quantile(data[k], .5), q3 = Stats.Quantile(data[k], .75), mx = data[k].Max();
                Pen p = new Pen(Pal[k], 3);
                g.DrawLine(p, cx, Y(mn), cx, Y(mx)); g.DrawLine(p, cx - bw / 4, Y(mn), cx + bw / 4, Y(mn)); g.DrawLine(p, cx - bw / 4, Y(mx), cx + bw / 4, Y(mx));
                g.FillRectangle(new SolidBrush(Color.FromArgb(70, Pal[k])), cx - bw / 2, Y(q3), bw, Y(q1) - Y(q3));
                g.DrawRectangle(p, cx - bw / 2, Y(q3), bw, Y(q1) - Y(q3));
                g.DrawLine(new Pen(Pal[k], 6), cx - bw / 2, Y(md), cx + bw / 2, Y(md));
                StringFormat sf = new StringFormat(); sf.Alignment = StringAlignment.Center; string lab = names[k].Replace(" con ", "\ncon ").Replace(" (", "\n(").Replace(" aleatoria", "\naleatoria").Replace(" aleatorias", "\naleatorias"); g.DrawString(lab, f, Brushes.Black, cx, H - B + 10, sf);
                for (int i = 0; i < data[k].Length; i++) { float jx = cx + bw / 2 + 14 + (i % 5) * 6; g.FillEllipse(new SolidBrush(Pal[k]), jx, Y(data[k][i]) - 3, 7, 7); }
            }
            g.TranslateTransform(8, (H + T) / 2 + 60); g.RotateTransform(-90); g.DrawString("Makespan (min)", f, Brushes.Black, 0, 0); g.ResetTransform();
            bmp.Save(path, ImageFormat.Png); g.Dispose(); bmp.Dispose();
        }

        public static void Gantt(string path, Instance ins, Decoder d, string title)
        {
            int W = 1200, rowH = 70, L = 150, R = 20, T = 60, B = 75, H = T + B + rowH * ins.M;
            Bitmap bmp = new Bitmap(W, H); Graphics g = Begin(bmp);
            int cmax = 0; for (int o = 0; o < ins.N; o++) cmax = Math.Max(cmax, d.Finish[o]);
            Func<double, float> X = x => (float)(L + (W - L - R) * x / cmax);
            Font f = new Font("Arial", 17), fs = new Font("Arial", 14, FontStyle.Bold), fb = new Font("Arial", 20, FontStyle.Bold);
            g.DrawString(title, fb, Brushes.Black, 10, 14);
            for (int t = 0; t <= cmax; t += 50) { g.DrawLine(new Pen(Color.FromArgb(225, 225, 225)), X(t), T, X(t), H - B); g.DrawString(t.ToString(), f, Brushes.Black, X(t) - 14, H - B + 6); }
            g.DrawString("Tiempo (min)", f, Brushes.Black, (W + L) / 2 - 45, H - B + 36);
            Color[] jc = new Color[ins.J];
            for (int j = 0; j < ins.J; j++) jc[j] = ColorFromHsv(360.0 * j / ins.J, 0.55, 0.92);
            for (int m = 0; m < ins.M; m++)
            {
                float y = T + rowH * m;
                g.DrawString(ins.MachineNames[m], f, Brushes.Black, 6, y + rowH / 2 - 12);
                g.DrawLine(Pens.Gray, L, y + rowH, W - R, y + rowH);
            }
            for (int o = 0; o < ins.N; o++)
            {
                float y = T + rowH * ins.OpMach[o] + 8, x1 = X(d.Start[o]), x2 = X(d.Finish[o]);
                g.FillRectangle(new SolidBrush(jc[ins.OpJob[o]]), x1, y, x2 - x1, rowH - 16); g.DrawRectangle(Pens.Black, x1, y, x2 - x1, rowH - 16);
                string lab = "J" + (ins.OpJob[o] + 1); SizeF sz = g.MeasureString(lab, fs);
                if (sz.Width < x2 - x1) g.DrawString(lab, fs, Brushes.Black, x1 + (x2 - x1 - sz.Width) / 2, y + (rowH - 16 - sz.Height) / 2);
            }
            g.DrawRectangle(Pens.Black, L, T, W - L - R, H - T - B);
            bmp.Save(path, ImageFormat.Png); g.Dispose(); bmp.Dispose();
        }

        static Color ColorFromHsv(double h, double s, double v)
        {
            double c = v * s, x = c * (1 - Math.Abs((h / 60) % 2 - 1)), m = v - c, r = 0, gg = 0, b = 0;
            if (h < 60) { r = c; gg = x; } else if (h < 120) { r = x; gg = c; } else if (h < 180) { gg = c; b = x; } else if (h < 240) { gg = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
            return Color.FromArgb((int)((r + m) * 255), (int)((gg + m) * 255), (int)((b + m) * 255));
        }
    }

    // ------------------------------------------------------------------ programa principal
    public class Program
    {
        const int Runs = 30, Jobs = 15, InstSeed = 2026;

        static string F(double v, string fmt) { return v.ToString(fmt, CultureInfo.InvariantCulture); }

        public static int Main(string[] args)
        {
            string outDir = args.Length > 0 ? args[0] : "resultados"; Directory.CreateDirectory(outDir);
            Instance ins = new Instance(Jobs, InstSeed);
            Console.WriteLine("Trabajos={0} Maquinas={1} Operaciones={2} CargaMaxMaquina={3} LongMaxTrabajo={4} CotaInferior={5}", ins.J, ins.M, ins.N, ins.MaxMachLoad, ins.MaxJobLen, ins.LowerBound);

            // instancia -> CSV
            StringBuilder sb = new StringBuilder("trabajo;secuencia_maquina(min)\r\n");
            for (int j = 0; j < ins.J; j++)
            {
                List<string> parts = new List<string>();
                for (int k = 0; k < ins.Len[j]; k++) { int o = ins.Off[j] + k; parts.Add(ins.MachineNames[ins.OpMach[o]] + "(" + ins.OpTime[o] + ")"); }
                sb.AppendLine("J" + (j + 1) + ";" + string.Join(" > ", parts.ToArray()));
            }
            File.WriteAllText(Path.Combine(outDir, "instancia.csv"), sb.ToString(), new UTF8Encoding(true));

            Codec[] codecs = { new BinaryCodec(ins), new PermCodec(ins), new KeysCodec(ins) };
            string[] names = { codecs[0].Name, codecs[1].Name, codecs[2].Name, "Búsqueda aleatoria" };
            RunResult[][] res = new RunResult[4][];
            for (int c = 0; c < 4; c++)
            {
                res[c] = new RunResult[Runs];
                for (int r = 0; r < Runs; r++) res[c][r] = c < 3 ? Ga.Run(ins, codecs[c], 1000 + r) : Ga.RandomSearch(ins, 1000 + r);
                Console.WriteLine("{0}: mejor={1} media={2:F1}", names[c], res[c].Min(x => x.Best), res[c].Average(x => x.Best));
            }

            // reglas de despacho como referencia (deterministas)
            Decoder dec = new Decoder(ins);
            double[] pr = new double[ins.N];
            for (int o = 0; o < ins.N; o++) pr[o] = ins.OpTime[o];
            int spt = dec.Decode(pr);
            for (int o = 0; o < ins.N; o++) { int rem = 0; for (int k = ins.OpPos[o]; k < ins.Len[ins.OpJob[o]]; k++) rem += ins.OpTime[ins.Off[ins.OpJob[o]] + k]; pr[o] = -rem; }
            int mwkr = dec.Decode(pr);
            for (int o = 0; o < ins.N; o++) pr[o] = ins.OpJob[o] * 100 + ins.OpPos[o];
            int fifoJob = dec.Decode(pr);
            Console.WriteLine("Reglas: SPT={0} MWKR={1} Orden-de-trabajos={2}", spt, mwkr, fifoJob);

            // corridas -> CSV
            sb = new StringBuilder("metodo;corrida;semilla;makespan;generacion_mejor;tiempo_ms;evaluaciones\r\n");
            for (int c = 0; c < 4; c++) for (int r = 0; r < Runs; r++) sb.AppendLine(string.Join(";", new[] { names[c], (r + 1).ToString(), (1000 + r).ToString(), res[c][r].Best.ToString(), res[c][r].GenFound.ToString(), res[c][r].Ms.ToString(), res[c][r].Evals.ToString() }));
            File.WriteAllText(Path.Combine(outDir, "corridas.csv"), sb.ToString(), new UTF8Encoding(true));

            // resumen -> CSV
            sb = new StringBuilder("metodo;mejor;media;peor;desv_est;mediana;brecha_media_%;gen_media_mejor;tiempo_medio_ms;corridas_en_cota\r\n");
            double[][] fin = new double[4][];
            for (int c = 0; c < 4; c++)
            {
                fin[c] = res[c].Select(x => (double)x.Best).ToArray();
                double mean = Stats.Mean(fin[c]);
                sb.AppendLine(string.Join(";", new[] { names[c], F(fin[c].Min(), "0"), F(mean, "0.00"), F(fin[c].Max(), "0"), F(Stats.Std(fin[c]), "0.00"), F(Stats.Quantile(fin[c], .5), "0.0"),
                    F(100 * (mean - ins.LowerBound) / ins.LowerBound, "0.00"), F(res[c].Average(x => x.GenFound), "0.0"), F(res[c].Average(x => x.Ms), "0.0"), fin[c].Count(v => v == ins.LowerBound).ToString() }));
            }
            sb.AppendLine("Cota inferior;" + ins.LowerBound);
            sb.AppendLine("Regla SPT;" + spt); sb.AppendLine("Regla MWKR;" + mwkr); sb.AppendLine("Orden de trabajos;" + fifoJob);
            File.WriteAllText(Path.Combine(outDir, "resumen.csv"), sb.ToString(), new UTF8Encoding(true));

            // pruebas U de Mann-Whitney por pares
            sb = new StringBuilder("A;B;z;p_bilateral\r\n");
            for (int a = 0; a < 4; a++) for (int b = a + 1; b < 4; b++)
            { double z, p; Stats.MannWhitney(fin[a], fin[b], out z, out p); sb.AppendLine(names[a] + ";" + names[b] + ";" + F(z, "0.000") + ";" + F(p, "0.0000")); Console.WriteLine("MWU {0} vs {1}: z={2:F2} p={3:F4}", names[a], names[b], z, p); }
            File.WriteAllText(Path.Combine(outDir, "pruebas_mann_whitney.csv"), sb.ToString(), new UTF8Encoding(true));

            // convergencia -> CSV y grafica
            double[][] curves = new double[4][];
            for (int c = 0; c < 4; c++) { curves[c] = new double[Ga.Gens + 1]; for (int g = 0; g <= Ga.Gens; g++) curves[c][g] = res[c].Average(x => x.BestPerGen[g]); }
            sb = new StringBuilder("generacion;" + string.Join(";", names) + "\r\n");
            for (int g = 0; g <= Ga.Gens; g++) sb.AppendLine(g + ";" + string.Join(";", curves.Select(cv => F(cv[g], "0.00")).ToArray()));
            File.WriteAllText(Path.Combine(outDir, "convergencia.csv"), sb.ToString(), new UTF8Encoding(true));
            Charts.Convergence(Path.Combine(outDir, "convergencia.png"), names, curves, ins.LowerBound);
            Charts.Boxplot(Path.Combine(outDir, "cajas.png"), names, fin, ins.LowerBound);

            // mejor calendario global
            int bc = 0, br = 0, bv = int.MaxValue;
            for (int c = 0; c < 3; c++) for (int r = 0; r < Runs; r++) if (res[c][r].Best < bv) { bv = res[c][r].Best; bc = c; br = r; }
            return Finish(ins, res, names, bc, br, outDir);
        }

        static int Finish(Instance ins, RunResult[][] res, string[] names, int bc, int br, string outDir)
        {
            Decoder dec = new Decoder(ins);
            int cmax = dec.Decode(res[bc][br].BestPriorities);
            Console.WriteLine("Mejor global: {0} (corrida {1}) makespan={2}", names[bc], br + 1, cmax);
            StringBuilder sb = new StringBuilder("trabajo;operacion;maquina;inicio;fin\r\n");
            for (int o = 0; o < ins.N; o++) sb.AppendLine("J" + (ins.OpJob[o] + 1) + ";" + (ins.OpPos[o] + 1) + ";" + ins.MachineNames[ins.OpMach[o]] + ";" + dec.Start[o] + ";" + dec.Finish[o]);
            File.WriteAllText(Path.Combine(outDir, "mejor_calendario.csv"), sb.ToString(), new UTF8Encoding(true));
            Charts.Gantt(Path.Combine(outDir, "gantt_mejor.png"), ins, dec, "Mejor calendario: " + names[bc] + " (makespan = " + cmax + " min)");
            return 0;
        }
    }
}
