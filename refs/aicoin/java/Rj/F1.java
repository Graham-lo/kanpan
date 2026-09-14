package Rj;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import java.util.List;
import java.util.Map;
import p167hg.AbstractC7609s;
import sp.aicoin_kline.chart.data.ScriptDrawData;
import sp.aicoin_kline.chart.data.ScriptIndicAction;
import sp.aicoin_kline.chart.data.ScriptIndicConfig;
import sp.aicoin_kline.core.KLineManager;

/* JADX INFO: loaded from: classes7.dex */
public final class F1 extends AbstractC2744r0 {

    /* JADX INFO: renamed from: l, reason: collision with root package name */
    public final Paint f19108l;

    /* JADX INFO: renamed from: m, reason: collision with root package name */
    public final Paint f19109m;

    /* JADX INFO: renamed from: n, reason: collision with root package name */
    public final int f19110n;

    /* JADX INFO: renamed from: o, reason: collision with root package name */
    public final float f19111o;

    /* JADX INFO: renamed from: p, reason: collision with root package name */
    public final Rect f19112p;

    public F1(C2732n c2732n, String str, String str2) {
        super(c2732n, str);
        KLineManager.a aVar = KLineManager.f142490O;
        aVar.a();
        this.f19112p = new Rect();
        Paint paint = new Paint();
        Paint.Style style = Paint.Style.FILL;
        paint.setStyle(style);
        paint.setColor(Color.parseColor("#FFB7BFC8"));
        this.f19108l = paint;
        Paint paint2 = new Paint();
        paint2.setStyle(style);
        paint2.setColor(Color.parseColor("#9E1B68"));
        Paint paint3 = new Paint();
        this.f19109m = paint3;
        paint3.setAntiAlias(true);
        paint3.setStyle(style);
        paint3.setTextAlign(Paint.Align.CENTER);
        paint3.setColor(-1);
        paint3.setTextSize(nk.l.p(aVar.a().i(), 2, 9.0f));
        Paint.FontMetrics fontMetrics = paint3.getFontMetrics();
        this.f19110n = (int) Math.ceil(fontMetrics.bottom - fontMetrics.top);
        this.f19111o = (-(((float) Math.ceil(fontMetrics.bottom - fontMetrics.top)) / 2)) - fontMetrics.top;
        nk.l.o(1, 1.0f);
        nk.l.o(1, 2.0f);
    }

    @Override // Rj.AbstractC2744r0
    public void g(Canvas canvas) {
        AbstractC2759w0 abstractC2759w0L;
        Map mapZ;
        ScriptIndicConfig config;
        List<ScriptIndicAction> action;
        List<ScriptIndicAction> listU1;
        boolean zBooleanValue;
        Double dN;
        Double dN2;
        ScriptIndicConfig config2;
        C2741q c2741qB = i().b();
        C2702d c2702dE = c2741qB.e(b());
        if (c2702dE == null || (abstractC2759w0L = c2741qB.l(b())) == null) {
            return;
        }
        c2702dE.y();
        int iY = c2702dE.y();
        List<ScriptDrawData> listB = nk.x.f134260a.b();
        if (listB == null || listB.isEmpty()) {
            return;
        }
        for (ScriptDrawData scriptDrawData : listB) {
            if (((scriptDrawData == null || (config2 = scriptDrawData.getConfig()) == null) ? null : config2.getAction()) != null && (mapZ = Sf.N.z(scriptDrawData.getCalculateHistoryData())) != null && !mapZ.isEmpty() && (config = scriptDrawData.getConfig()) != null && (action = config.getAction()) != null && (listU1 = Sf.z.u1(action)) != null) {
                Map.Entry entry = (Map.Entry) Sf.z.p0(mapZ.entrySet());
                Map map = entry != null ? (Map) entry.getValue() : null;
                for (ScriptIndicAction scriptIndicAction : listU1) {
                    String action2 = scriptIndicAction.getAction();
                    int iHashCode = action2.hashCode();
                    if (iHashCode != -2020167279) {
                        if (iHashCode != -405487794) {
                            if (iHashCode == 3443937 && action2.equals("plot")) {
                                Boolean excludeRange = scriptIndicAction.getExcludeRange();
                                zBooleanValue = excludeRange != null ? excludeRange.booleanValue() : false;
                                if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && !zBooleanValue && map != null) {
                                    String series = scriptIndicAction.getSeries();
                                    if (series == null) {
                                        series = "0";
                                    }
                                    String str = (String) map.get(series);
                                    if (str == null) {
                                        str = "0.0";
                                    }
                                    Double dN3 = Ah.v.n(str);
                                    double dDoubleValue = dN3 != null ? dN3.doubleValue() : 0.0d;
                                    if (dDoubleValue != 0.0d) {
                                        v(abstractC2759w0L, canvas, iY, dDoubleValue);
                                    }
                                }
                            }
                        } else if (action2.equals("plotCandle")) {
                            Boolean excludeRange2 = scriptIndicAction.getExcludeRange();
                            zBooleanValue = excludeRange2 != null ? excludeRange2.booleanValue() : false;
                            if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && !zBooleanValue) {
                                Map.Entry entry2 = (Map.Entry) Sf.z.p0(mapZ.entrySet());
                                Map map2 = entry2 != null ? (Map) entry2.getValue() : null;
                                if (map2 != null) {
                                    String close = scriptIndicAction.getClose();
                                    String str2 = (String) map2.get(close != null ? close : "");
                                    double dDoubleValue2 = (str2 == null || (dN = Ah.v.n(str2)) == null) ? 0.0d : dN.doubleValue();
                                    if (dDoubleValue2 != 0.0d) {
                                        v(abstractC2759w0L, canvas, iY, dDoubleValue2);
                                    }
                                }
                            }
                        }
                    } else if (action2.equals("plotOhlc")) {
                        Boolean excludeRange3 = scriptIndicAction.getExcludeRange();
                        zBooleanValue = excludeRange3 != null ? excludeRange3.booleanValue() : false;
                        if (AbstractC7609s.f(scriptIndicAction.getTrackPrice(), Boolean.TRUE) && !zBooleanValue) {
                            Map.Entry entry3 = (Map.Entry) Sf.z.p0(mapZ.entrySet());
                            Map map3 = entry3 != null ? (Map) entry3.getValue() : null;
                            if (map3 != null) {
                                String close2 = scriptIndicAction.getClose();
                                String str3 = (String) map3.get(close2 != null ? close2 : "");
                                double dDoubleValue3 = (str3 == null || (dN2 = Ah.v.n(str3)) == null) ? 0.0d : dN2.doubleValue();
                                if (dDoubleValue3 != 0.0d) {
                                    v(abstractC2759w0L, canvas, iY, dDoubleValue3);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Override // Rj.AbstractC2744r0
    public void t() {
    }

    @Override // Rj.AbstractC2744r0
    public void u(mk.a aVar) {
    }

    public final void v(AbstractC2759w0 abstractC2759w0, Canvas canvas, float f10, double d10) {
        this.f19109m.getTextBounds(String.valueOf(d10), 0, String.valueOf(d10).length(), this.f19112p);
        float fB = f10 + Xj.a.b(100);
        float fP = abstractC2759w0.P(d10);
        float f11 = this.f19110n >> 1;
        canvas.drawRect(f10, fP - f11, fB, fP + f11, this.f19108l);
        canvas.drawText(nk.A.b(d10, KLineManager.f142490O.a().j()), Xj.a.b(25) + f10, fP + this.f19111o, this.f19109m);
    }
}
