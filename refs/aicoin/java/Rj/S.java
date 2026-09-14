package Rj;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.TextView;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import org.apache.tika.utils.StringUtils;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.R;
import sp.aicoin_kline.chart.Chart;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class S {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public final Context f19237a;

    /* JADX INFO: renamed from: b, reason: collision with root package name */
    public final boolean f19238b;

    /* JADX INFO: renamed from: c, reason: collision with root package name */
    public PopupWindow f19239c;

    public interface a {
        void a();

        void b();
    }

    public S(Context context, boolean z10) {
        this.f19237a = context;
        this.f19238b = z10;
    }

    public static final void a(int i10, List list, List list2, Chart chart, a aVar, S s10, View view) {
        if (i10 >= 0 && i10 < list.size() - 1) {
            Qf.v vVar = (Qf.v) list2.get(i10);
            int i11 = i10 + 1;
            list2.set(i10, list2.get(i11));
            list2.set(i11, vVar);
            ArrayList arrayList = new ArrayList();
            ArrayList arrayList2 = new ArrayList();
            int i12 = 0;
            for (Object obj : list2) {
                int i13 = i12 + 1;
                if (i12 < 0) {
                    Sf.r.x();
                }
                Qf.v vVar2 = (Qf.v) obj;
                if (((Boolean) vVar2.f()).booleanValue()) {
                    arrayList2.add(new Qf.p(Integer.valueOf(i12), vVar2.e()));
                } else {
                    arrayList.add(vVar2.e());
                }
                i12 = i13;
            }
            if (!arrayList.isEmpty()) {
                C2760w1.f19594a.b(arrayList);
            }
            if (!arrayList2.isEmpty()) {
                C2760w1.f19594a.d(arrayList2);
            }
            if (chart != null) {
                chart.setCurrentDataSource("default");
            }
        }
        C2738p.f19487a.r();
        aVar.a();
        PopupWindow popupWindow = s10.f19239c;
        if (popupWindow != null) {
            popupWindow.dismiss();
        }
    }

    public static final void b(int i10, List list, Chart chart, a aVar, S s10, View view) {
        if (i10 > 0) {
            Qf.v vVar = (Qf.v) list.get(i10);
            int i11 = i10 - 1;
            list.set(i10, list.get(i11));
            list.set(i11, vVar);
            ArrayList arrayList = new ArrayList();
            ArrayList arrayList2 = new ArrayList();
            int i12 = 0;
            for (Object obj : list) {
                int i13 = i12 + 1;
                if (i12 < 0) {
                    Sf.r.x();
                }
                Qf.v vVar2 = (Qf.v) obj;
                if (((Boolean) vVar2.f()).booleanValue()) {
                    arrayList2.add(new Qf.p(Integer.valueOf(i12), vVar2.e()));
                } else {
                    arrayList.add(vVar2.e());
                }
                i12 = i13;
            }
            if (!arrayList.isEmpty()) {
                C2760w1.f19594a.b(arrayList);
            }
            if (!arrayList2.isEmpty()) {
                C2760w1.f19594a.d(arrayList2);
            }
            if (chart != null) {
                chart.setCurrentDataSource("default");
            }
        }
        C2738p.f19487a.r();
        aVar.b();
        PopupWindow popupWindow = s10.f19239c;
        if (popupWindow != null) {
            popupWindow.dismiss();
        }
    }

    public static final void c(S s10, LinearLayout linearLayout) {
        TextView textView = new TextView(s10.f19237a);
        textView.setLayoutParams(new LinearLayout.LayoutParams(Xj.a.b(1), -1));
        textView.setText("");
        textView.setBackgroundColor(((Number) p162hb.e.c(KLineManager.f142490O.a().f0() == 1, Integer.valueOf(Color.parseColor("#E7E8E7")), Integer.valueOf(Color.parseColor("#2A2E37")))).intValue());
        linearLayout.addView(textView);
    }

    public static final void d(String str, S s10, View view) {
        C2738p.f19487a.j(str, s10.f19238b);
        PopupWindow popupWindow = s10.f19239c;
        if (popupWindow != null) {
            popupWindow.dismiss();
        }
    }

    public static final void e(String str, S s10, View view) {
        C2738p.f19487a.i(str, s10.f19238b);
        PopupWindow popupWindow = s10.f19239c;
        if (popupWindow != null) {
            popupWindow.dismiss();
        }
    }

    public final void f(Chart chart, int i10, int i11, String str, String str2, a aVar) {
        int i12;
        String str3;
        LinearLayout linearLayout;
        List list;
        int i13;
        int i14;
        S s10 = this;
        KLineManager.a aVar2 = KLineManager.f142490O;
        int iIntValue = ((Number) p162hb.e.c(aVar2.a().f0() == 1, -1, Integer.valueOf(Color.parseColor("#1F2126")))).intValue();
        int iIntValue2 = ((Number) p162hb.e.c(aVar2.a().f0() == 1, Integer.valueOf(Color.parseColor("#E7E8E7")), Integer.valueOf(Color.parseColor("#1F2126")))).intValue();
        GradientDrawable gradientDrawable = new GradientDrawable();
        gradientDrawable.setShape(0);
        gradientDrawable.setColor(iIntValue);
        gradientDrawable.setCornerRadius(Xj.a.b(4));
        gradientDrawable.setStroke(1, iIntValue2);
        List listG = C2760w1.f19594a.g();
        ArrayList arrayList = new ArrayList();
        arrayList.addAll(listG);
        String strI = Ah.x.I(Ah.x.I(Ah.x.I(Ah.x.I(Ah.x.I(str.toUpperCase(), "_", "", false, 4, null), "_", "", false, 4, null), "-", "", false, 4, null), StringUtils.SPACE, "", false, 4, null), StringUtils.SPACE, "", false, 4, null);
        Iterator it = arrayList.iterator();
        int i15 = 0;
        while (true) {
            if (!it.hasNext()) {
                i12 = -1;
                break;
            } else {
                if (Ah.y.T(Ah.x.I(Ah.x.I(Ah.x.I(Ah.x.I(Ah.x.I(((String) ((Qf.v) it.next()).e()).toUpperCase(), "_", "", false, 4, null), "_", "", false, 4, null), "-", "", false, 4, null), StringUtils.SPACE, "", false, 4, null), StringUtils.SPACE, "", false, 4, null), strI, false, 2, null)) {
                    i12 = i15;
                    break;
                }
                i15++;
            }
        }
        boolean z10 = i12 == 0;
        boolean z11 = i12 == arrayList.size() - 1;
        LinearLayout linearLayout2 = new LinearLayout(s10.f19237a);
        linearLayout2.setOrientation(0);
        linearLayout2.setLayoutParams(new ViewGroup.LayoutParams(-2, -2));
        linearLayout2.setBackground(gradientDrawable);
        linearLayout2.setPadding(Xj.a.b(2), Xj.a.b(2), Xj.a.b(2), Xj.a.b(2));
        if (Ah.y.T(str, "publicScript", false, 2, null) || s10.f19238b) {
            str3 = str2;
        } else {
            str3 = (i12 < 0 || i12 >= arrayList.size()) ? str : (String) ((Qf.v) arrayList.get(i12)).e();
        }
        if (AbstractC7609s.f(str, "Position")) {
            str3 = "OI";
        }
        TextView textView = new TextView(s10.f19237a);
        textView.setText(str3.toUpperCase(Locale.ROOT));
        textView.setTextSize(Xj.a.d(4));
        KLineManager.a aVar3 = KLineManager.f142490O;
        textView.setTextColor(((Number) p162hb.e.c(aVar3.a().f0() == 1, Integer.valueOf(Color.parseColor("#333333")), Integer.valueOf(Color.parseColor("#FFFFFF")))).intValue());
        textView.setPadding(Xj.a.b(6), Xj.a.b(4), Xj.a.b(6), Xj.a.b(4));
        textView.setGravity(16);
        textView.setLayoutParams(new LinearLayout.LayoutParams(-2, -1));
        linearLayout2.addView(textView);
        c(s10, linearLayout2);
        int iIntValue3 = ((Number) p162hb.e.c(aVar3.a().f0() == 1, Integer.valueOf(R.mipmap.move_up_icon), Integer.valueOf(R.mipmap.move_up_icon_night))).intValue();
        if (z10) {
            linearLayout = linearLayout2;
            list = listG;
            i13 = 10;
            i14 = 12;
        } else {
            Drawable drawableE = S1.b.e(s10.f19237a, iIntValue3);
            i14 = 12;
            TextView textView2 = new TextView(s10.f19237a);
            textView2.setText("");
            i13 = 10;
            textView2.setPadding(Xj.a.b(10), Xj.a.b(4), Xj.a.b(10), Xj.a.b(4));
            if (drawableE != null) {
                int iB = Xj.a.b(12);
                drawableE.setBounds(0, 0, iB, iB);
                textView2.setCompoundDrawables(drawableE, null, null, null);
            }
            textView2.setLayoutParams(new LinearLayout.LayoutParams(-2, -2));
            linearLayout = linearLayout2;
            list = listG;
            textView2.setOnClickListener(new N(i12, list, chart, aVar, s10));
            linearLayout.addView(textView2);
        }
        boolean z12 = !z10;
        if (!z10 && !z11) {
            c(s10, linearLayout);
        }
        if (!z11) {
            Drawable drawableE2 = S1.b.e(s10.f19237a, ((Number) p162hb.e.c(aVar3.a().f0() == 1, Integer.valueOf(R.mipmap.move_down_icon), Integer.valueOf(R.mipmap.move_down_icon_night))).intValue());
            TextView textView3 = new TextView(s10.f19237a);
            textView3.setText("");
            textView3.setPadding(Xj.a.b(i13), Xj.a.b(4), Xj.a.b(i13), Xj.a.b(4));
            if (drawableE2 != null) {
                int iB2 = Xj.a.b(i14);
                drawableE2.setBounds(0, 0, iB2, iB2);
                textView3.setCompoundDrawables(drawableE2, null, null, null);
            }
            textView3.setLayoutParams(new LinearLayout.LayoutParams(-2, -2));
            O o10 = new O(i12, arrayList, list, chart, aVar, s10);
            s10 = s10;
            textView3.setOnClickListener(o10);
            linearLayout.addView(textView3);
            z12 = true;
        }
        if (z12) {
            c(s10, linearLayout);
        }
        Drawable drawableE3 = S1.b.e(s10.f19237a, R.drawable.kline_info_dialog_setting_icon);
        TextView textView4 = new TextView(s10.f19237a);
        textView4.setText("");
        textView4.setPadding(Xj.a.b(i13), Xj.a.b(4), Xj.a.b(i13), Xj.a.b(4));
        if (drawableE3 != null) {
            int iB3 = Xj.a.b(i14);
            drawableE3.setBounds(0, 0, iB3, iB3);
            textView4.setCompoundDrawables(drawableE3, null, null, null);
        }
        textView4.setLayoutParams(new LinearLayout.LayoutParams(-2, -2));
        textView4.setOnClickListener(new P(str, s10));
        linearLayout.addView(textView4);
        c(s10, linearLayout);
        Drawable drawableE4 = S1.b.e(s10.f19237a, R.drawable.kline_info_dialog_delete_icon);
        TextView textView5 = new TextView(s10.f19237a);
        textView5.setText("");
        textView5.setPadding(Xj.a.b(i13), Xj.a.b(4), Xj.a.b(i13), Xj.a.b(4));
        if (drawableE4 != null) {
            int iB4 = Xj.a.b(i14);
            drawableE4.setBounds(0, 0, iB4, iB4);
            textView5.setCompoundDrawables(drawableE4, null, null, null);
        }
        textView5.setLayoutParams(new LinearLayout.LayoutParams(-2, -2));
        textView5.setOnClickListener(new Q(str, s10));
        linearLayout.addView(textView5);
        PopupWindow popupWindow = new PopupWindow((View) linearLayout, -2, -2, true);
        popupWindow.setElevation(Xj.a.b(i13));
        popupWindow.setOutsideTouchable(true);
        PopupWindow popupWindow2 = s10.f19239c;
        if (popupWindow2 != null) {
            popupWindow2.setBackgroundDrawable(new ColorDrawable(-1));
        }
        s10.f19239c = popupWindow;
        popupWindow.showAtLocation(chart, 0, i10, i11);
    }
}
