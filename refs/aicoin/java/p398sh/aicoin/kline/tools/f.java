package p398sh.aicoin.kline.tools;

import Qf.InterfaceC2632j;
import Qf.k;
import Qf.n;
import Qf.w;
import Sf.AbstractC2803q;
import Sf.AbstractC2804s;
import Sf.M;
import Sf.N;
import Sf.V;
import Sf.r;
import Sf.z;
import android.content.Context;
import app.aicoin.base.kline.R;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.apache.tika.metadata.DublinCore;
import p292ng.i;
import p398sh.aicoin.kline.entity.b;
import p398sh.aicoin.kline.entity.c;
import p398sh.aicoin.kline.entity.d;

/* JADX INFO: loaded from: classes7.dex */
public final class f {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final f f140674a = new f();

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public static final Map f140675b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public static final Map f140676c;

    /* JADX INFO: renamed from: d, reason: collision with root package name */
    public static final ArrayList f140677d;

    /* JADX INFO: renamed from: e, reason: collision with root package name */
    public static final ArrayList f140678e;

    /* JADX INFO: renamed from: f, reason: collision with root package name */
    public static final InterfaceC2632j f140679f;

    /* JADX INFO: renamed from: g, reason: collision with root package name */
    public static final InterfaceC2632j f140680g;

    /* JADX INFO: renamed from: h, reason: collision with root package name */
    public static final InterfaceC2632j f140681h;

    public /* synthetic */ class a {

        /* JADX INFO: renamed from: a, reason: collision with root package name */
        public static final /* synthetic */ int[] f140682a;

        static {
            int[] iArr = new int[p398sh.aicoin.kline.indic.a.values().length];
            try {
                iArr[p398sh.aicoin.kline.indic.a.Main.ordinal()] = 1;
            } catch (NoSuchFieldError unused) {
            }
            try {
                iArr[p398sh.aicoin.kline.indic.a.Sub.ordinal()] = 2;
            } catch (NoSuchFieldError unused2) {
            }
            f140682a = iArr;
        }
    }

    static {
        Map mapN = N.n(w.a(1, "ma"), w.a(2, "ema"), w.a(3, "boll"), w.a(4, "sar"), w.a(5, "ene"), w.a(6, DublinCore.PREFIX_DC), w.a(7, "alligator"), w.a(8, "ichimoku"), w.a(9, "kc"), w.a(10, "td"), w.a(11, "bbi"), w.a(12, "ai-srl"), w.a(13, "ai-largeorder"), w.a(15, "ai-aggtrade"), w.a(16, "vpvr"), w.a(18, "18"), w.a(21, "liqheatmap"));
        f140675b = mapN;
        Map mapN2 = N.n(w.a(11, "volume"), w.a(1, "macd"), w.a(2, "kdj"), w.a(18, "skdj"), w.a(5, "obv"), w.a(3, "rsi"), w.a(4, "stochrsi"), w.a(6, "trix"), w.a(7, "wr"), w.a(8, "cci"), w.a(9, "roc"), w.a(10, "atr"), w.a(13, "dmi"), w.a(14, "vr"), w.a(15, "psy"), w.a(16, "bias"), w.a(17, "smi"), w.a(19, "dma"), w.a(20, "mtm"), w.a(21, "bbw"), w.a(12, "fundflow"), w.a(22, "position"), w.a(31, "lsur"), w.a(32, "basis"), w.a(33, "tvolume"), w.a(34, "ftbs"), w.a(23, "ttsi"), w.a(24, "ttmu"), w.a(35, "mlr"), w.a(36, "bsv"), w.a(25, "brar"), w.a(26, "emv"), w.a(27, "mfi"), w.a(28, "boll"), w.a(29, "dpo"), w.a(30, "ao"), w.a(43, "fr"), w.a(44, "pfr"), w.a(37, "ai-fdi"), w.a(38, "ai-pd"), w.a(39, "ai-li"), w.a(40, "ai-bsi"), w.a(41, "ai-netvol"), w.a(42, "ai-bst"), w.a(46, "publicScript-cvd"), w.a(47, "publicScript-cvdCandle"), w.a(48, "publicScript-mc"), w.a(49, "publicScript-positionMc"), w.a(50, "publicScript-basisOkex"), w.a(51, "publicScript-basisBinance"), w.a(52, "publicScript-fundingRate"), w.a(53, "publicScript-coinContract"), w.a(54, "publicScript-usdtContract"), w.a(55, "publicScript-activeTradeValue"), w.a(56, "publicScript-activeTradeVolume"), w.a(57, "publicScript-activeTradeCount"));
        f140676c = mapN2;
        f140677d = new ArrayList(mapN.values());
        f140678e = new ArrayList(mapN2.values());
        f140679f = k.b(new c());
        f140680g = k.b(new d());
        f140681h = k.b(new e());
    }

    public static final Map A() {
        Set<Map.Entry> setEntrySet = f140675b.entrySet();
        LinkedHashMap linkedHashMap = new LinkedHashMap(i.f(M.e(AbstractC2804s.y(setEntrySet, 10)), 16));
        for (Map.Entry entry : setEntrySet) {
            linkedHashMap.put((String) entry.getValue(), Integer.valueOf(((Number) entry.getKey()).intValue()));
        }
        return linkedHashMap;
    }

    public static final Set B() {
        return V.h("ai-srl", "ai-largeorder", "ai-aggtrade", "vpvr", "ai-fdi", "ai-pd", "ai-li", "ai-bsi", "ai-netvol", "publicScript-cvd", "publicScript-cvdCandle", "publicScript-positionMc", "publicScript-basisOkex", "publicScript-basisBinance", "publicScript-activeTradeValue", "publicScript-activeTradeVolume", "publicScript-activeTradeCount");
    }

    public static final Map C() {
        Set<Map.Entry> setEntrySet = f140676c.entrySet();
        LinkedHashMap linkedHashMap = new LinkedHashMap(i.f(M.e(AbstractC2804s.y(setEntrySet, 10)), 16));
        for (Map.Entry entry : setEntrySet) {
            linkedHashMap.put((String) entry.getValue(), Integer.valueOf(((Number) entry.getKey()).intValue()));
        }
        return linkedHashMap;
    }

    public static final List d() {
        int i10 = R.string.ui_kline_drawing_show_name_hori_straight_line;
        List listT = r.t(new p398sh.aicoin.kline.entity.a("CHoriStraightLineObject", i10, R.mipmap.ui_kline_drawing_hori_straight_line), new p398sh.aicoin.kline.entity.a("CHoriStraightLineObject", i10, R.mipmap.ui_kline_drawing_child_hori_straight_line), new p398sh.aicoin.kline.entity.a("CHoriRayLineObject", R.string.ui_kline_drawing_show_name_hori_ray_line, R.mipmap.ui_kline_drawing_child_hori_ray_line), new p398sh.aicoin.kline.entity.a("CHoriSegLineObject", R.string.ui_kline_drawing_show_name_hori_seg_line, R.mipmap.ui_kline_drawing_child_hori_seg_line));
        int i11 = R.string.ui_kline_drawing_show_name_strait_line;
        List listT2 = r.t(new p398sh.aicoin.kline.entity.a("CStraightLineObject", i11, R.mipmap.ui_kline_drawing_straight_line), new p398sh.aicoin.kline.entity.a("CStraightLineObject", i11, R.mipmap.ui_kline_drawing_child_straight_line), new p398sh.aicoin.kline.entity.a("CRayLineObject", R.string.ui_kline_drawing_show_name_ray_line, R.mipmap.ui_kline_drawing_child_ray_line), new p398sh.aicoin.kline.entity.a("CSegLineObject", R.string.ui_kline_drawing_show_name_seg_line, R.mipmap.ui_kline_drawing_child_seg_line), new p398sh.aicoin.kline.entity.a("CArrowLineObject", R.string.ui_kline_drawing_show_name_arrow_line, R.mipmap.ui_kline_drawing_child_hori_arrow_line), new p398sh.aicoin.kline.entity.a("CVertiStraightLineObject", R.string.ui_kline_drawing_show_name_verti_strait_line, R.mipmap.ui_kline_drawing_child_verti_strait_line));
        List listT3 = r.t(new p398sh.aicoin.kline.entity.a("CPriceLineObject", R.string.ui_kline_drawing_show_name_price_line, R.mipmap.ui_kline_drawing_price_line));
        List listT4 = r.t(new p398sh.aicoin.kline.entity.a("CTriParallelLineObject", R.string.ui_kline_drawing_show_name_parallel_tunnel_line, R.mipmap.ui_kline_drawing_parallel_tunnel_line));
        int i12 = R.string.ui_kline_drawing_show_name_fib_retrace_line;
        int i13 = R.mipmap.ui_kline_drawing_fib_retrace_line;
        return r.t(listT, listT2, listT3, listT4, r.t(new p398sh.aicoin.kline.entity.a("CFibRetraceObject", i12, i13), new p398sh.aicoin.kline.entity.a("CFibRetraceObject", i12, i13), new p398sh.aicoin.kline.entity.a("CFibSpiralObject", R.string.ui_kline_drawing_show_name_fib_circle, R.mipmap.ui_kline_drawing_fib_spiral), new p398sh.aicoin.kline.entity.a("CFibFansObject", R.string.ui_kline_drawing_show_name_fib_sector, R.mipmap.ui_kline_drawing_fib_sector), new p398sh.aicoin.kline.entity.a("CFibExtensionObject", R.string.ui_kline_drawing_show_name_fib_ext, R.mipmap.ui_kline_drawing_fib_extance), new p398sh.aicoin.kline.entity.a("CFibRetraceSegLineObject", R.string.ui_kline_drawing_show_name_fib_segment, R.mipmap.ui_kline_drawing_fib_segment)), r.t(new p398sh.aicoin.kline.entity.a("CPriceDateRulerObject", R.string.ui_kline_drawing_show_name_space_time_rule, R.drawable.ui_kline_draw_bar_ic_space_time_rule)), r.t(new p398sh.aicoin.kline.entity.a("CRectangleObject", R.string.ui_kline_drawing_show_name_rectangle, R.drawable.ui_kline_draw_bar_ic_retangle)));
    }

    public static final List e() {
        return r.t(new b(R.mipmap.ui_kline_floating_drawing_menu_line_width_thin, new float[]{0.0f, 0.0f}), new b(R.mipmap.ui_kline_floating_drawing_menu_line_style_short, new float[]{2.0f, 2.0f}), new b(R.mipmap.ui_kline_floating_drawing_menu_line_style_long, new float[]{4.0f, 6.0f}));
    }

    public static final List f() {
        return r.t(new c(R.mipmap.ui_kline_floating_drawing_menu_line_width_thin, 1.0f), new c(R.mipmap.ui_kline_floating_drawing_menu_line_width_normal, 2.0f), new c(R.mipmap.ui_kline_floating_drawing_menu_line_width_thick, 3.0f), new c(R.mipmap.ui_kline_floating_drawing_menu_line_width_very_thick, 4.0f));
    }

    public static final List g() {
        ArrayList arrayList = new ArrayList();
        arrayList.add(new d(1, R.string.ui_kline_indicator_name_ma, 0));
        arrayList.add(new d(2, R.string.ui_kline_indicator_name_ema, 0));
        arrayList.add(new d(3, R.string.ui_kline_indicator_name_boll, 0));
        arrayList.add(new d(4, R.string.ui_kline_indicator_name_sar, 0));
        arrayList.add(new d(5, R.string.ui_kline_indicator_name_ene, 0));
        arrayList.add(new d(6, R.string.ui_kline_indicator_name_dc, 0));
        arrayList.add(new d(7, R.string.ui_kline_indicator_name_alligator, 0));
        arrayList.add(new d(8, R.string.ui_kline_indicator_name_ichimoku, 0));
        arrayList.add(new d(9, R.string.ui_kline_indicator_name_kc, 0));
        arrayList.add(new d(10, R.string.ui_kline_indicator_name_td, 0));
        arrayList.add(new d(11, R.string.ui_kline_indicator_name_bbi, 0));
        arrayList.add(new d(13, R.string.ui_kline_indicator_name_ai_large_order, 0));
        arrayList.add(new d(15, R.string.ui_kline_indicator_name_ai_large_trade, 0));
        arrayList.add(new d(21, R.string.ui_kline_indicator_name_heat_liquidation, 0));
        return arrayList;
    }

    public static final List h() {
        ArrayList arrayList = new ArrayList();
        arrayList.add(new d(11, R.string.ui_kline_indicator_name_volume, 0));
        arrayList.add(new d(1, R.string.ui_kline_indicator_name_macd, 0));
        arrayList.add(new d(2, R.string.ui_kline_indicator_name_kdj, 0));
        arrayList.add(new d(18, R.string.ui_kline_indicator_name_skdj, 0));
        arrayList.add(new d(5, R.string.ui_kline_indicator_name_obv, 0));
        arrayList.add(new d(3, R.string.ui_kline_indicator_name_rsi, 0));
        arrayList.add(new d(4, R.string.ui_kline_indicator_name_stoch_rsi, 0));
        arrayList.add(new d(6, R.string.ui_kline_indicator_name_trix, 0));
        arrayList.add(new d(7, R.string.ui_kline_indicator_name_wr, 0));
        arrayList.add(new d(8, R.string.ui_kline_indicator_name_cci, 0));
        arrayList.add(new d(9, R.string.ui_kline_indicator_name_roc, 0));
        arrayList.add(new d(10, R.string.ui_kline_indicator_name_atr, 0));
        arrayList.add(new d(13, R.string.ui_kline_indicator_name_dmi, 0));
        arrayList.add(new d(14, R.string.ui_kline_indicator_name_vr, 0));
        arrayList.add(new d(15, R.string.ui_kline_indicator_name_psy, 0));
        arrayList.add(new d(16, R.string.ui_kline_indicator_name_bias, 0));
        arrayList.add(new d(17, R.string.ui_kline_indicator_name_smi, 0));
        arrayList.add(new d(19, R.string.ui_kline_indicator_name_dma, 0));
        arrayList.add(new d(20, R.string.ui_kline_indicator_name_mtm, 0));
        arrayList.add(new d(21, R.string.ui_kline_indicator_name_bbw, 0));
        arrayList.add(new d(12, R.string.ui_kline_indicator_name_fund_flow, 0));
        arrayList.add(new d(22, R.string.ui_kline_indicator_name_position, 0));
        arrayList.add(new d(31, R.string.ui_kline_indicator_name_lsur, 0));
        arrayList.add(new d(32, R.string.ui_kline_indicator_name_basis, 0));
        arrayList.add(new d(33, R.string.ui_kline_indicator_name_tvolume, 0));
        arrayList.add(new d(34, R.string.ui_kline_indicator_name_ftbs, 0));
        arrayList.add(new d(23, R.string.ui_kline_indicator_name_ttsi, 0));
        arrayList.add(new d(24, R.string.ui_kline_indicator_name_ttmu, 0));
        arrayList.add(new d(35, R.string.ui_kline_indicator_name_mlr, 0));
        arrayList.add(new d(36, R.string.ui_kline_indicator_name_bsv, 0));
        arrayList.add(new d(25, R.string.ui_kline_indicator_name_brar, 0));
        arrayList.add(new d(26, R.string.ui_kline_indicator_name_emv, 0));
        arrayList.add(new d(27, R.string.ui_kline_indicator_name_mfi, 0));
        arrayList.add(new d(28, R.string.ui_kline_indicator_name_boll, 0));
        arrayList.add(new d(29, R.string.ui_kline_indicator_name_dpo, 0));
        arrayList.add(new d(30, R.string.ui_kline_indicator_name_ao, 0));
        arrayList.add(new d(43, R.string.ui_kline_indicator_name_fr, 0));
        arrayList.add(new d(44, R.string.ui_kline_indicator_name_pfr, 0));
        arrayList.add(new d(46, R.string.ui_kline_indicator_name_cvd, 0));
        arrayList.add(new d(47, R.string.ui_kline_indicator_name_kcvd, 0));
        arrayList.add(new d(48, R.string.ui_kline_indicator_name_mc, 0));
        arrayList.add(new d(49, R.string.ui_kline_indicator_name_hmc, 0));
        arrayList.add(new d(50, R.string.ui_kline_indicator_name_bso, 0));
        arrayList.add(new d(51, R.string.ui_kline_indicator_name_bsb, 0));
        arrayList.add(new d(52, R.string.ui_kline_indicator_name_kfr, 0));
        arrayList.add(new d(53, R.string.ui_kline_indicator_name_chk, 0));
        arrayList.add(new d(54, R.string.ui_kline_indicator_name_uhk, 0));
        arrayList.add(new d(55, R.string.ui_kline_indicator_name_ata, 0));
        arrayList.add(new d(56, R.string.ui_kline_indicator_name_atv, 0));
        arrayList.add(new d(57, R.string.ui_kline_indicator_name_atn, 0));
        return arrayList;
    }

    public static final List j() {
        ArrayList arrayList = new ArrayList();
        arrayList.add(new d(1, R.string.ui_kline_compare_type_price, 0));
        arrayList.add(new d(0, R.string.ui_kline_compare_type_growth_rate, 0));
        return arrayList;
    }

    public static final String o(Context context, int i10) {
        int i11;
        if (i10 == 15) {
            i11 = R.string.ui_kline_indicator_name_ai_large_trade;
        } else if (i10 == 16) {
            i11 = R.string.ui_kline_indicator_name_ai_cyq;
        } else if (i10 != 21) {
            switch (i10) {
                case 1:
                    i11 = R.string.ui_kline_indicator_name_ma;
                    break;
                case 2:
                    i11 = R.string.ui_kline_indicator_name_ema;
                    break;
                case 3:
                    i11 = R.string.ui_kline_indicator_name_boll;
                    break;
                case 4:
                    i11 = R.string.ui_kline_indicator_name_sar;
                    break;
                case 5:
                    i11 = R.string.ui_kline_indicator_name_ene;
                    break;
                case 6:
                    i11 = R.string.ui_kline_indicator_name_dc;
                    break;
                case 7:
                    i11 = R.string.ui_kline_indicator_name_alligator;
                    break;
                case 8:
                    i11 = R.string.ui_kline_indicator_name_ichimoku;
                    break;
                case 9:
                    i11 = R.string.ui_kline_indicator_name_kc;
                    break;
                case 10:
                    i11 = R.string.ui_kline_indicator_name_td;
                    break;
                case 11:
                    i11 = R.string.ui_kline_indicator_name_bbi;
                    break;
                case 12:
                    i11 = R.string.ui_kline_indicator_setting_home_item_name_ai_srl;
                    break;
                case 13:
                    i11 = R.string.ui_kline_indicator_name_ai_large_order;
                    break;
                default:
                    i11 = R.string.kline_indicator_title_average;
                    break;
            }
        } else {
            i11 = R.string.ui_kline_indicator_name_heat_liquidation;
        }
        return context.getString(i11);
    }

    public static final int p(int i10) {
        if (i10 == 15) {
            return R.string.ui_kline_indicator_name_ai_large_trade;
        }
        if (i10 == 16) {
            return R.string.ui_kline_indicator_name_ai_cyq;
        }
        if (i10 == 21) {
            return R.string.ui_kline_indicator_name_heat_liquidation;
        }
        switch (i10) {
            case 1:
                return R.string.ui_kline_indicator_name_ma;
            case 2:
                return R.string.ui_kline_indicator_name_ema;
            case 3:
                return R.string.ui_kline_indicator_name_boll;
            case 4:
                return R.string.ui_kline_indicator_name_sar;
            case 5:
                return R.string.ui_kline_indicator_name_ene;
            case 6:
                return R.string.ui_kline_indicator_name_dc;
            case 7:
                return R.string.ui_kline_indicator_name_alligator;
            case 8:
                return R.string.ui_kline_indicator_name_ichimoku;
            case 9:
                return R.string.ui_kline_indicator_name_kc;
            case 10:
                return R.string.ui_kline_indicator_name_td;
            case 11:
                return R.string.ui_kline_indicator_name_bbi;
            case 12:
                return R.string.ui_kline_indicator_setting_home_item_name_ai_srl;
            case 13:
                return R.string.ui_kline_indicator_name_ai_large_order;
            default:
                return R.string.kline_indicator_title_average;
        }
    }

    public static final String q(Context context, int i10) {
        int i11;
        switch (i10) {
            case 1:
                i11 = R.string.ui_kline_indicator_name_macd;
                break;
            case 2:
                i11 = R.string.ui_kline_indicator_name_kdj;
                break;
            case 3:
                i11 = R.string.ui_kline_indicator_name_rsi;
                break;
            case 4:
                i11 = R.string.ui_kline_indicator_name_stoch_rsi;
                break;
            case 5:
                i11 = R.string.ui_kline_indicator_name_obv;
                break;
            case 6:
                i11 = R.string.ui_kline_indicator_name_trix;
                break;
            case 7:
                i11 = R.string.ui_kline_indicator_name_wr;
                break;
            case 8:
                i11 = R.string.ui_kline_indicator_name_cci;
                break;
            case 9:
                i11 = R.string.ui_kline_indicator_name_roc;
                break;
            case 10:
                i11 = R.string.ui_kline_indicator_name_atr;
                break;
            case 11:
                i11 = R.string.ui_kline_indicator_name_volume;
                break;
            case 12:
                i11 = R.string.ui_kline_indicator_name_fund_flow;
                break;
            case 13:
                i11 = R.string.ui_kline_indicator_name_dmi;
                break;
            case 14:
                i11 = R.string.ui_kline_indicator_name_vr;
                break;
            case 15:
                i11 = R.string.ui_kline_indicator_name_psy;
                break;
            case 16:
                i11 = R.string.ui_kline_indicator_name_bias;
                break;
            case 17:
                i11 = R.string.ui_kline_indicator_name_smi;
                break;
            case 18:
                i11 = R.string.ui_kline_indicator_name_skdj;
                break;
            case 19:
                i11 = R.string.ui_kline_indicator_name_dma;
                break;
            case 20:
                i11 = R.string.ui_kline_indicator_name_mtm;
                break;
            case 21:
                i11 = R.string.ui_kline_indicator_name_bbw;
                break;
            case 22:
                i11 = R.string.ui_kline_indicator_name_position;
                break;
            case 23:
                i11 = R.string.ui_kline_indicator_name_ttsi;
                break;
            case 24:
                i11 = R.string.ui_kline_indicator_name_ttmu;
                break;
            case 25:
                i11 = R.string.ui_kline_indicator_name_brar;
                break;
            case 26:
                i11 = R.string.ui_kline_indicator_name_emv;
                break;
            case 27:
                i11 = R.string.ui_kline_indicator_name_mfi;
                break;
            case 28:
                i11 = R.string.ui_kline_indicator_name_boll;
                break;
            case 29:
                i11 = R.string.ui_kline_indicator_name_dpo;
                break;
            case 30:
                i11 = R.string.ui_kline_indicator_name_ao;
                break;
            case 31:
                i11 = R.string.ui_kline_indicator_name_lsur;
                break;
            case 32:
                i11 = R.string.ui_kline_indicator_name_basis;
                break;
            case 33:
                i11 = R.string.ui_kline_indicator_name_tvolume;
                break;
            case 34:
                i11 = R.string.ui_kline_indicator_name_ftbs;
                break;
            case 35:
                i11 = R.string.ui_kline_indicator_name_mlr;
                break;
            case 36:
                i11 = R.string.ui_kline_indicator_name_bsv;
                break;
            case 37:
                i11 = R.string.ui_kline_indicator_name_ai_fdi;
                break;
            case 38:
                i11 = R.string.ui_kline_indicator_name_ai_pd;
                break;
            case 39:
                i11 = R.string.ui_kline_indicator_name_ai_li;
                break;
            case 40:
                i11 = R.string.ui_kline_indicator_name_ai_bsi;
                break;
            case 41:
                i11 = R.string.ui_kline_indicator_name_ai_net_vol;
                break;
            case 42:
                i11 = R.string.ui_kline_indicator_name_ai_bst;
                break;
            case 43:
                i11 = R.string.ui_kline_indicator_name_fr;
                break;
            case 44:
                i11 = R.string.ui_kline_indicator_name_pfr;
                break;
            case 45:
            default:
                i11 = R.string.kline_indicator_title_index;
                break;
            case 46:
                i11 = R.string.ui_kline_indicator_name_cvd;
                break;
            case 47:
                i11 = R.string.ui_kline_indicator_name_kcvd;
                break;
            case 48:
                i11 = R.string.ui_kline_indicator_name_mc;
                break;
            case 49:
                i11 = R.string.ui_kline_indicator_name_hmc;
                break;
            case 50:
                i11 = R.string.ui_kline_indicator_name_bso;
                break;
            case 51:
                i11 = R.string.ui_kline_indicator_name_bsb;
                break;
            case 52:
                i11 = R.string.ui_kline_indicator_name_kfr;
                break;
            case 53:
                i11 = R.string.ui_kline_indicator_name_chk;
                break;
            case 54:
                i11 = R.string.ui_kline_indicator_name_uhk;
                break;
            case 55:
                i11 = R.string.ui_kline_indicator_name_ata;
                break;
            case 56:
                i11 = R.string.ui_kline_indicator_name_atv;
                break;
            case 57:
                i11 = R.string.ui_kline_indicator_name_atn;
                break;
        }
        return context.getString(i11);
    }

    public static final int r(int i10) {
        switch (i10) {
            case 1:
                return R.string.ui_kline_indicator_name_macd;
            case 2:
                return R.string.ui_kline_indicator_name_kdj;
            case 3:
                return R.string.ui_kline_indicator_name_rsi;
            case 4:
                return R.string.ui_kline_indicator_name_stoch_rsi;
            case 5:
                return R.string.ui_kline_indicator_name_obv;
            case 6:
                return R.string.ui_kline_indicator_name_trix;
            case 7:
                return R.string.ui_kline_indicator_name_wr;
            case 8:
                return R.string.ui_kline_indicator_name_cci;
            case 9:
                return R.string.ui_kline_indicator_name_roc;
            case 10:
                return R.string.ui_kline_indicator_name_atr;
            case 11:
                return R.string.ui_kline_indicator_name_volume;
            case 12:
                return R.string.ui_kline_indicator_name_fund_flow;
            case 13:
                return R.string.ui_kline_indicator_name_dmi;
            case 14:
                return R.string.ui_kline_indicator_name_vr;
            case 15:
                return R.string.ui_kline_indicator_name_psy;
            case 16:
                return R.string.ui_kline_indicator_name_bias;
            case 17:
                return R.string.ui_kline_indicator_name_smi;
            case 18:
                return R.string.ui_kline_indicator_name_skdj;
            case 19:
                return R.string.ui_kline_indicator_name_dma;
            case 20:
                return R.string.ui_kline_indicator_name_mtm;
            case 21:
                return R.string.ui_kline_indicator_name_bbw;
            case 22:
                return R.string.ui_kline_indicator_name_position;
            case 23:
                return R.string.ui_kline_indicator_name_ttsi;
            case 24:
                return R.string.ui_kline_indicator_name_ttmu;
            case 25:
                return R.string.ui_kline_indicator_name_brar;
            case 26:
                return R.string.ui_kline_indicator_name_emv;
            case 27:
                return R.string.ui_kline_indicator_name_mfi;
            case 28:
                return R.string.ui_kline_indicator_name_boll;
            case 29:
                return R.string.ui_kline_indicator_name_dpo;
            case 30:
                return R.string.ui_kline_indicator_name_ao;
            case 31:
                return R.string.ui_kline_indicator_name_lsur;
            case 32:
                return R.string.ui_kline_indicator_name_basis;
            case 33:
                return R.string.ui_kline_indicator_name_tvolume;
            case 34:
                return R.string.ui_kline_indicator_name_ftbs;
            case 35:
                return R.string.ui_kline_indicator_name_mlr;
            case 36:
                return R.string.ui_kline_indicator_name_bsv;
            case 37:
                return R.string.ui_kline_indicator_name_ai_fdi;
            case 38:
                return R.string.ui_kline_indicator_name_ai_pd;
            case 39:
                return R.string.ui_kline_indicator_name_ai_li;
            case 40:
                return R.string.ui_kline_indicator_name_ai_bsi;
            case 41:
                return R.string.ui_kline_indicator_name_ai_net_vol;
            case 42:
                return R.string.ui_kline_indicator_name_ai_bst;
            case 43:
                return R.string.ui_kline_indicator_name_fr;
            case 44:
                return R.string.ui_kline_indicator_name_pfr;
            case 45:
            default:
                return R.string.kline_indicator_title_index;
            case 46:
                return R.string.ui_kline_indicator_name_cvd;
            case 47:
                return R.string.ui_kline_indicator_name_kcvd;
            case 48:
                return R.string.ui_kline_indicator_name_mc;
            case 49:
                return R.string.ui_kline_indicator_name_hmc;
            case 50:
                return R.string.ui_kline_indicator_name_bso;
            case 51:
                return R.string.ui_kline_indicator_name_bsb;
            case 52:
                return R.string.ui_kline_indicator_name_kfr;
            case 53:
                return R.string.ui_kline_indicator_name_chk;
            case 54:
                return R.string.ui_kline_indicator_name_uhk;
            case 55:
                return R.string.ui_kline_indicator_name_ata;
            case 56:
                return R.string.ui_kline_indicator_name_atv;
            case 57:
                return R.string.ui_kline_indicator_name_atn;
        }
    }

    public static final String s() {
        nk.d dVar = nk.d.f134196a;
        return dVar.a(dVar.b("CMagnifierObject"));
    }

    public final List i() {
        ArrayList arrayList = new ArrayList();
        arrayList.add(new d(7, R.string.ui_kline_compare_info_window, R.drawable.ui_kline_compare_info_window_visible_selector));
        return arrayList;
    }

    public final String k(Context context, int i10) {
        int i11;
        if (i10 != 13) {
            switch (i10) {
                case 37:
                    i11 = R.string.ui_kline_features_tips_ai_fdi;
                    break;
                case 38:
                    i11 = R.string.ui_kline_features_tips_ai_pd;
                    break;
                case 39:
                    i11 = R.string.ui_kline_features_tips_ai_li;
                    break;
                case 40:
                    i11 = R.string.ui_kline_features_tips_ai_bsi;
                    break;
                case 41:
                    i11 = R.string.ui_kline_features_tips_ai_net_vol;
                    break;
                default:
                    switch (i10) {
                        case 46:
                            i11 = R.string.ui_kline_features_tips_cvd;
                            break;
                        case 47:
                            i11 = R.string.ui_kline_features_tips_kcvd;
                            break;
                        case 48:
                            i11 = R.string.ui_kline_features_tips_mc;
                            break;
                        case 49:
                            i11 = R.string.ui_kline_features_tips_hmc;
                            break;
                        case 50:
                            i11 = R.string.ui_kline_features_tips_bso;
                            break;
                        case 51:
                            i11 = R.string.ui_kline_features_tips_bsb;
                            break;
                        case 52:
                            i11 = R.string.ui_kline_features_tips_kfr;
                            break;
                        case 53:
                            i11 = R.string.ui_kline_features_tips_chk;
                            break;
                        case 54:
                            i11 = R.string.ui_kline_features_tips_uhk;
                            break;
                        case 55:
                            i11 = R.string.ui_kline_features_tips_ata;
                            break;
                        case 56:
                            i11 = R.string.ui_kline_features_tips_atv;
                            break;
                        case 57:
                            i11 = R.string.ui_kline_features_tips_atn;
                            break;
                        default:
                            i11 = R.string.ui_base_empty_string;
                            break;
                    }
                    break;
            }
        } else {
            i11 = R.string.ui_kline_features_tips_large_order;
        }
        return context.getString(i11);
    }

    public final String l(Context context, int i10) {
        return context.getString(i10 == 13 ? R.string.ui_kline_features_tips_warning : R.string.ui_base_empty_string);
    }

    public final List m() {
        return z.S0(z.S0(f140677d, f140678e), AbstractC2803q.e(u()));
    }

    public final List n(p398sh.aicoin.kline.indic.a aVar) {
        int i10 = a.f140682a[aVar.ordinal()];
        if (i10 != 1) {
            if (i10 != 2) {
                throw new n();
            }
            Map map = f140676c;
            ArrayList arrayList = new ArrayList();
            Iterator it = map.entrySet().iterator();
            while (it.hasNext()) {
                String str = (String) ((Map.Entry) it.next()).getValue();
                if (str != null) {
                    arrayList.add(str);
                }
            }
            return arrayList;
        }
        Map map2 = f140675b;
        ArrayList arrayList2 = new ArrayList();
        Iterator it2 = map2.entrySet().iterator();
        while (it2.hasNext()) {
            String str2 = (String) ((Map.Entry) it2.next()).getValue();
            if (str2 != null) {
                arrayList2.add(str2);
            }
        }
        ArrayList arrayList3 = new ArrayList();
        for (Object obj : arrayList2) {
            if (!p398sh.aicoin.kline.indic.b.f140605a.b((String) obj)) {
                arrayList3.add(obj);
            }
        }
        return arrayList3;
    }

    public final Map t() {
        return (Map) f140680g.getValue();
    }

    public final String u() {
        return "patterns";
    }

    public final Set v() {
        return (Set) f140679f.getValue();
    }

    public final Map w() {
        return (Map) f140681h.getValue();
    }

    public final String x(p398sh.aicoin.kline.indic.a aVar, int i10) {
        int i11 = a.f140682a[aVar.ordinal()];
        if (i11 == 1) {
            return (String) f140675b.get(Integer.valueOf(i10));
        }
        if (i11 == 2) {
            return (String) f140676c.get(Integer.valueOf(i10));
        }
        throw new n();
    }

    public final int y(p398sh.aicoin.kline.indic.a aVar, String str) {
        int i10 = a.f140682a[aVar.ordinal()];
        if (i10 == 1) {
            Integer num = (Integer) t().get(str);
            if (num != null) {
                return num.intValue();
            }
            return 0;
        }
        if (i10 != 2) {
            throw new n();
        }
        Integer num2 = (Integer) w().get(str);
        if (num2 != null) {
            return num2.intValue();
        }
        return 0;
    }

    public final boolean z(String str) {
        return v().contains(str);
    }
}
