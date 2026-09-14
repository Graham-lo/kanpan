package sp.aicoin_kline.chart.data.drawing;

import android.graphics.PointF;
import androidx.annotation.Keep;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import kk.d;
import kk.h;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000B\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\u0010\u0011\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0002\n\u0002\u0018\u0002\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010!\n\u0002\u0018\u0002\n\u0002\b\u0004\n\u0002\u0018\u0002\n\u0002\b\u0010\n\u0002\u0010\b\n\u0002\b\u001c\b\u0087\b\u0018\u00002\u00020\u0001:\u0002=>BI\u0012\f\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002\u0012\u0006\u0010\u0006\u001a\u00020\u0005\u0012\u0006\u0010\u0007\u001a\u00020\u0005\u0012\b\u0010\t\u001a\u0004\u0018\u00010\b\u0012\b\b\u0002\u0010\u000b\u001a\u00020\n\u0012\u000e\b\u0002\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\r0\f¢\u0006\u0004\b\u000f\u0010\u0010J\u0015\u0010\u0013\u001a\u00020\u00122\u0006\u0010\u0011\u001a\u00020\u0000¢\u0006\u0004\b\u0013\u0010\u0014J\u0016\u0010\u0015\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002HÆ\u0003¢\u0006\u0004\b\u0015\u0010\u0016J\u0010\u0010\u0017\u001a\u00020\u0005HÆ\u0003¢\u0006\u0004\b\u0017\u0010\u0018J\u0010\u0010\u0019\u001a\u00020\u0005HÆ\u0003¢\u0006\u0004\b\u0019\u0010\u0018J\u0012\u0010\u001a\u001a\u0004\u0018\u00010\bHÆ\u0003¢\u0006\u0004\b\u001a\u0010\u001bJ\u0010\u0010\u001c\u001a\u00020\nHÆ\u0003¢\u0006\u0004\b\u001c\u0010\u001dJ\u0016\u0010\u001e\u001a\b\u0012\u0004\u0012\u00020\r0\fHÆ\u0003¢\u0006\u0004\b\u001e\u0010\u001fJZ\u0010 \u001a\u00020\u00002\u000e\b\u0002\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00022\b\b\u0002\u0010\u0006\u001a\u00020\u00052\b\b\u0002\u0010\u0007\u001a\u00020\u00052\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\b2\b\b\u0002\u0010\u000b\u001a\u00020\n2\u000e\b\u0002\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\r0\fHÆ\u0001¢\u0006\u0004\b \u0010!J\u0010\u0010\"\u001a\u00020\u0005HÖ\u0001¢\u0006\u0004\b\"\u0010\u0018J\u0010\u0010$\u001a\u00020#HÖ\u0001¢\u0006\u0004\b$\u0010%J\u001a\u0010'\u001a\u00020\n2\b\u0010&\u001a\u0004\u0018\u00010\u0001HÖ\u0003¢\u0006\u0004\b'\u0010(R(\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0004\u0010)\u001a\u0004\b*\u0010\u0016\"\u0004\b+\u0010,R\u0017\u0010\u0006\u001a\u00020\u00058\u0006¢\u0006\f\n\u0004\b\u0006\u0010-\u001a\u0004\b.\u0010\u0018R\"\u0010\u0007\u001a\u00020\u00058\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0007\u0010-\u001a\u0004\b/\u0010\u0018\"\u0004\b0\u00101R$\u0010\t\u001a\u0004\u0018\u00010\b8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\t\u00102\u001a\u0004\b3\u0010\u001b\"\u0004\b4\u00105R\"\u0010\u000b\u001a\u00020\n8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u000b\u00106\u001a\u0004\b\u000b\u0010\u001d\"\u0004\b7\u00108R(\u0010\u000e\u001a\b\u0012\u0004\u0012\u00020\r0\f8\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u000e\u00109\u001a\u0004\b:\u0010\u001f\"\u0004\b;\u0010<¨\u0006?"}, d2 = {"Lsp/aicoin_kline/chart/data/drawing/DrawingItem;", "", "", "Lsp/aicoin_kline/chart/data/drawing/DrawingPoint;", "points", "", "name", "id", "Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;", "options", "", "isSelected", "", "Landroid/graphics/PointF;", "decisionPoints", "<init>", "([Lsp/aicoin_kline/chart/data/drawing/DrawingPoint;Ljava/lang/String;Ljava/lang/String;Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;ZLjava/util/List;)V", "targetItem", "LQf/H;", "copyWith", "(Lsp/aicoin_kline/chart/data/drawing/DrawingItem;)V", "component1", "()[Lsp/aicoin_kline/chart/data/drawing/DrawingPoint;", "component2", "()Ljava/lang/String;", "component3", "component4", "()Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;", "component5", "()Z", "component6", "()Ljava/util/List;", "copy", "([Lsp/aicoin_kline/chart/data/drawing/DrawingPoint;Ljava/lang/String;Ljava/lang/String;Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;ZLjava/util/List;)Lsp/aicoin_kline/chart/data/drawing/DrawingItem;", "toString", "", "hashCode", "()I", "other", "equals", "(Ljava/lang/Object;)Z", "[Lsp/aicoin_kline/chart/data/drawing/DrawingPoint;", "getPoints", "setPoints", "([Lsp/aicoin_kline/chart/data/drawing/DrawingPoint;)V", "Ljava/lang/String;", "getName", "getId", "setId", "(Ljava/lang/String;)V", "Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;", "getOptions", "setOptions", "(Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;)V", "Z", "setSelected", "(Z)V", "Ljava/util/List;", "getDecisionPoints", "setDecisionPoints", "(Ljava/util/List;)V", "Options", "PercentageCell", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class DrawingItem {
    private List<PointF> decisionPoints;
    private String id;
    private boolean isSelected;
    private final String name;
    private Options options;
    private DrawingPoint[] points;

    @Keep
    @Metadata(d1 = {"\u00008\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u0007\n\u0000\n\u0002\u0010\b\n\u0002\b\u0003\n\u0002\u0010!\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0005\n\u0002\u0010 \n\u0002\u0018\u0002\n\u0002\b9\b\u0087\b\u0018\u00002\u00020\u0001B£\u0001\u0012\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u0003\u0012\u0010\b\u0002\u0010\n\u001a\n\u0012\u0004\u0012\u00020\u0005\u0018\u00010\u000b\u0012\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\r\u0012\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u0005\u0012\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u0007\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0005\u0012\u0010\b\u0002\u0010\u0012\u001a\n\u0012\u0004\u0012\u00020\u0014\u0018\u00010\u0013¢\u0006\u0004\b\u0015\u0010\u0016J\u0010\u0010;\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u0010\u0010<\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u0010\u0010=\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010!J\u0010\u0010>\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010!J\u0010\u0010?\u001a\u0004\u0018\u00010\u0003HÆ\u0003¢\u0006\u0002\u0010\u0017J\u0011\u0010@\u001a\n\u0012\u0004\u0012\u00020\u0005\u0018\u00010\u000bHÆ\u0003J\u000b\u0010A\u001a\u0004\u0018\u00010\rHÆ\u0003J\u0010\u0010B\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u0010\u0010C\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010!J\u0010\u0010D\u001a\u0004\u0018\u00010\u0007HÆ\u0003¢\u0006\u0002\u0010!J\u0010\u0010E\u001a\u0004\u0018\u00010\u0005HÆ\u0003¢\u0006\u0002\u0010\u001cJ\u0011\u0010F\u001a\n\u0012\u0004\u0012\u00020\u0014\u0018\u00010\u0013HÆ\u0003Jª\u0001\u0010G\u001a\u00020\u00002\n\b\u0002\u0010\u0002\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0004\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u0006\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\b\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\t\u001a\u0004\u0018\u00010\u00032\u0010\b\u0002\u0010\n\u001a\n\u0012\u0004\u0012\u00020\u0005\u0018\u00010\u000b2\n\b\u0002\u0010\f\u001a\u0004\u0018\u00010\r2\n\b\u0002\u0010\u000e\u001a\u0004\u0018\u00010\u00052\n\b\u0002\u0010\u000f\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u0010\u001a\u0004\u0018\u00010\u00072\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00052\u0010\b\u0002\u0010\u0012\u001a\n\u0012\u0004\u0012\u00020\u0014\u0018\u00010\u0013HÆ\u0001¢\u0006\u0002\u0010HJ\u0013\u0010I\u001a\u00020\u00032\b\u0010J\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010K\u001a\u00020\u0007HÖ\u0001J\t\u0010L\u001a\u00020\rHÖ\u0001R\u001e\u0010\u0002\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u001a\u001a\u0004\b\u0002\u0010\u0017\"\u0004\b\u0018\u0010\u0019R\u001e\u0010\u0004\u001a\u0004\u0018\u00010\u0005X\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u001f\u001a\u0004\b\u001b\u0010\u001c\"\u0004\b\u001d\u0010\u001eR\u001e\u0010\u0006\u001a\u0004\u0018\u00010\u0007X\u0086\u000e¢\u0006\u0010\n\u0002\u0010$\u001a\u0004\b \u0010!\"\u0004\b\"\u0010#R\u001e\u0010\b\u001a\u0004\u0018\u00010\u0007X\u0086\u000e¢\u0006\u0010\n\u0002\u0010$\u001a\u0004\b%\u0010!\"\u0004\b&\u0010#R\u001e\u0010\t\u001a\u0004\u0018\u00010\u0003X\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u001a\u001a\u0004\b'\u0010\u0017\"\u0004\b(\u0010\u0019R\"\u0010\n\u001a\n\u0012\u0004\u0012\u00020\u0005\u0018\u00010\u000bX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b)\u0010*\"\u0004\b+\u0010,R\u001c\u0010\f\u001a\u0004\u0018\u00010\rX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b-\u0010.\"\u0004\b/\u00100R\u001e\u0010\u000e\u001a\u0004\u0018\u00010\u0005X\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u001f\u001a\u0004\b1\u0010\u001c\"\u0004\b2\u0010\u001eR\u001e\u0010\u000f\u001a\u0004\u0018\u00010\u0007X\u0086\u000e¢\u0006\u0010\n\u0002\u0010$\u001a\u0004\b3\u0010!\"\u0004\b4\u0010#R\u001e\u0010\u0010\u001a\u0004\u0018\u00010\u0007X\u0086\u000e¢\u0006\u0010\n\u0002\u0010$\u001a\u0004\b5\u0010!\"\u0004\b6\u0010#R\u001e\u0010\u0011\u001a\u0004\u0018\u00010\u0005X\u0086\u000e¢\u0006\u0010\n\u0002\u0010\u001f\u001a\u0004\b7\u0010\u001c\"\u0004\b8\u0010\u001eR\"\u0010\u0012\u001a\n\u0012\u0004\u0012\u00020\u0014\u0018\u00010\u0013X\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b9\u0010*\"\u0004\b:\u0010,¨\u0006M"}, d2 = {"Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;", "", "isLocked", "", "lineWidth", "", "lineColor", "", "background", "showBackground", "lineDash", "", "fontText", "", "fontSize", "fontWeight", "fontColor", "fontWidth", "percentageList", "", "Lsp/aicoin_kline/chart/data/drawing/DrawingItem$PercentageCell;", "<init>", "(Ljava/lang/Boolean;Ljava/lang/Float;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/util/List;Ljava/lang/String;Ljava/lang/Float;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Float;Ljava/util/List;)V", "()Ljava/lang/Boolean;", "setLocked", "(Ljava/lang/Boolean;)V", "Ljava/lang/Boolean;", "getLineWidth", "()Ljava/lang/Float;", "setLineWidth", "(Ljava/lang/Float;)V", "Ljava/lang/Float;", "getLineColor", "()Ljava/lang/Integer;", "setLineColor", "(Ljava/lang/Integer;)V", "Ljava/lang/Integer;", "getBackground", "setBackground", "getShowBackground", "setShowBackground", "getLineDash", "()Ljava/util/List;", "setLineDash", "(Ljava/util/List;)V", "getFontText", "()Ljava/lang/String;", "setFontText", "(Ljava/lang/String;)V", "getFontSize", "setFontSize", "getFontWeight", "setFontWeight", "getFontColor", "setFontColor", "getFontWidth", "setFontWidth", "getPercentageList", "setPercentageList", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "copy", "(Ljava/lang/Boolean;Ljava/lang/Float;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Boolean;Ljava/util/List;Ljava/lang/String;Ljava/lang/Float;Ljava/lang/Integer;Ljava/lang/Integer;Ljava/lang/Float;Ljava/util/List;)Lsp/aicoin_kline/chart/data/drawing/DrawingItem$Options;", "equals", "other", "hashCode", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class Options {
        private Integer background;
        private Integer fontColor;
        private Float fontSize;
        private String fontText;
        private Integer fontWeight;
        private Float fontWidth;
        private Boolean isLocked;
        private Integer lineColor;
        private List<Float> lineDash;
        private Float lineWidth;
        private List<PercentageCell> percentageList;
        private Boolean showBackground;

        public Options() {
            this(null, null, null, null, null, null, null, null, null, null, null, null, 4095, null);
        }

        public Options(Boolean bool, Float f10, Integer num, Integer num2, Boolean bool2, List<Float> list, String str, Float f11, Integer num3, Integer num4, Float f12, List<PercentageCell> list2) {
            this.isLocked = bool;
            this.lineWidth = f10;
            this.lineColor = num;
            this.background = num2;
            this.showBackground = bool2;
            this.lineDash = list;
            this.fontText = str;
            this.fontSize = f11;
            this.fontWeight = num3;
            this.fontColor = num4;
            this.fontWidth = f12;
            this.percentageList = list2;
        }

        public /* synthetic */ Options(Boolean bool, Float f10, Integer num, Integer num2, Boolean bool2, List list, String str, Float f11, Integer num3, Integer num4, Float f12, List list2, int i10, DefaultConstructorMarker defaultConstructorMarker) {
            this((i10 & 1) != 0 ? Boolean.FALSE : bool, (i10 & 2) != 0 ? Float.valueOf(1.0f) : f10, (i10 & 4) != 0 ? null : num, (i10 & 8) != 0 ? null : num2, (i10 & 16) != 0 ? Boolean.FALSE : bool2, (i10 & 32) != 0 ? null : list, (i10 & 64) != 0 ? null : str, (i10 & 128) != 0 ? null : f11, (i10 & 256) != 0 ? null : num3, (i10 & 512) != 0 ? null : num4, (i10 & 1024) != 0 ? null : f12, (i10 & 2048) != 0 ? null : list2);
        }

        /* JADX WARN: Multi-variable type inference failed */
        public static /* synthetic */ Options copy$default(Options options, Boolean bool, Float f10, Integer num, Integer num2, Boolean bool2, List list, String str, Float f11, Integer num3, Integer num4, Float f12, List list2, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                bool = options.isLocked;
            }
            if ((i10 & 2) != 0) {
                f10 = options.lineWidth;
            }
            if ((i10 & 4) != 0) {
                num = options.lineColor;
            }
            if ((i10 & 8) != 0) {
                num2 = options.background;
            }
            if ((i10 & 16) != 0) {
                bool2 = options.showBackground;
            }
            if ((i10 & 32) != 0) {
                list = options.lineDash;
            }
            if ((i10 & 64) != 0) {
                str = options.fontText;
            }
            if ((i10 & 128) != 0) {
                f11 = options.fontSize;
            }
            if ((i10 & 256) != 0) {
                num3 = options.fontWeight;
            }
            if ((i10 & 512) != 0) {
                num4 = options.fontColor;
            }
            if ((i10 & 1024) != 0) {
                f12 = options.fontWidth;
            }
            if ((i10 & 2048) != 0) {
                list2 = options.percentageList;
            }
            Float f13 = f12;
            List list3 = list2;
            Integer num5 = num3;
            Integer num6 = num4;
            String str2 = str;
            Float f14 = f11;
            Boolean bool3 = bool2;
            List list4 = list;
            return options.copy(bool, f10, num, num2, bool3, list4, str2, f14, num5, num6, f13, list3);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final Boolean getIsLocked() {
            return this.isLocked;
        }

        /* JADX INFO: renamed from: component10, reason: from getter */
        public final Integer getFontColor() {
            return this.fontColor;
        }

        /* JADX INFO: renamed from: component11, reason: from getter */
        public final Float getFontWidth() {
            return this.fontWidth;
        }

        public final List<PercentageCell> component12() {
            return this.percentageList;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final Float getLineWidth() {
            return this.lineWidth;
        }

        /* JADX INFO: renamed from: component3, reason: from getter */
        public final Integer getLineColor() {
            return this.lineColor;
        }

        /* JADX INFO: renamed from: component4, reason: from getter */
        public final Integer getBackground() {
            return this.background;
        }

        /* JADX INFO: renamed from: component5, reason: from getter */
        public final Boolean getShowBackground() {
            return this.showBackground;
        }

        public final List<Float> component6() {
            return this.lineDash;
        }

        /* JADX INFO: renamed from: component7, reason: from getter */
        public final String getFontText() {
            return this.fontText;
        }

        /* JADX INFO: renamed from: component8, reason: from getter */
        public final Float getFontSize() {
            return this.fontSize;
        }

        /* JADX INFO: renamed from: component9, reason: from getter */
        public final Integer getFontWeight() {
            return this.fontWeight;
        }

        public final Options copy(Boolean isLocked, Float lineWidth, Integer lineColor, Integer background, Boolean showBackground, List<Float> lineDash, String fontText, Float fontSize, Integer fontWeight, Integer fontColor, Float fontWidth, List<PercentageCell> percentageList) {
            return new Options(isLocked, lineWidth, lineColor, background, showBackground, lineDash, fontText, fontSize, fontWeight, fontColor, fontWidth, percentageList);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof Options)) {
                return false;
            }
            Options options = (Options) other;
            return AbstractC7609s.f(this.isLocked, options.isLocked) && AbstractC7609s.f(this.lineWidth, options.lineWidth) && AbstractC7609s.f(this.lineColor, options.lineColor) && AbstractC7609s.f(this.background, options.background) && AbstractC7609s.f(this.showBackground, options.showBackground) && AbstractC7609s.f(this.lineDash, options.lineDash) && AbstractC7609s.f(this.fontText, options.fontText) && AbstractC7609s.f(this.fontSize, options.fontSize) && AbstractC7609s.f(this.fontWeight, options.fontWeight) && AbstractC7609s.f(this.fontColor, options.fontColor) && AbstractC7609s.f(this.fontWidth, options.fontWidth) && AbstractC7609s.f(this.percentageList, options.percentageList);
        }

        public final Integer getBackground() {
            return this.background;
        }

        public final Integer getFontColor() {
            return this.fontColor;
        }

        public final Float getFontSize() {
            return this.fontSize;
        }

        public final String getFontText() {
            return this.fontText;
        }

        public final Integer getFontWeight() {
            return this.fontWeight;
        }

        public final Float getFontWidth() {
            return this.fontWidth;
        }

        public final Integer getLineColor() {
            return this.lineColor;
        }

        public final List<Float> getLineDash() {
            return this.lineDash;
        }

        public final Float getLineWidth() {
            return this.lineWidth;
        }

        public final List<PercentageCell> getPercentageList() {
            return this.percentageList;
        }

        public final Boolean getShowBackground() {
            return this.showBackground;
        }

        public int hashCode() {
            Boolean bool = this.isLocked;
            int iHashCode = (bool == null ? 0 : bool.hashCode()) * 31;
            Float f10 = this.lineWidth;
            int iHashCode2 = (iHashCode + (f10 == null ? 0 : f10.hashCode())) * 31;
            Integer num = this.lineColor;
            int iHashCode3 = (iHashCode2 + (num == null ? 0 : num.hashCode())) * 31;
            Integer num2 = this.background;
            int iHashCode4 = (iHashCode3 + (num2 == null ? 0 : num2.hashCode())) * 31;
            Boolean bool2 = this.showBackground;
            int iHashCode5 = (iHashCode4 + (bool2 == null ? 0 : bool2.hashCode())) * 31;
            List<Float> list = this.lineDash;
            int iHashCode6 = (iHashCode5 + (list == null ? 0 : list.hashCode())) * 31;
            String str = this.fontText;
            int iHashCode7 = (iHashCode6 + (str == null ? 0 : str.hashCode())) * 31;
            Float f11 = this.fontSize;
            int iHashCode8 = (iHashCode7 + (f11 == null ? 0 : f11.hashCode())) * 31;
            Integer num3 = this.fontWeight;
            int iHashCode9 = (iHashCode8 + (num3 == null ? 0 : num3.hashCode())) * 31;
            Integer num4 = this.fontColor;
            int iHashCode10 = (iHashCode9 + (num4 == null ? 0 : num4.hashCode())) * 31;
            Float f12 = this.fontWidth;
            int iHashCode11 = (iHashCode10 + (f12 == null ? 0 : f12.hashCode())) * 31;
            List<PercentageCell> list2 = this.percentageList;
            return iHashCode11 + (list2 != null ? list2.hashCode() : 0);
        }

        public final Boolean isLocked() {
            return this.isLocked;
        }

        public final void setBackground(Integer num) {
            this.background = num;
        }

        public final void setFontColor(Integer num) {
            this.fontColor = num;
        }

        public final void setFontSize(Float f10) {
            this.fontSize = f10;
        }

        public final void setFontText(String str) {
            this.fontText = str;
        }

        public final void setFontWeight(Integer num) {
            this.fontWeight = num;
        }

        public final void setFontWidth(Float f10) {
            this.fontWidth = f10;
        }

        public final void setLineColor(Integer num) {
            this.lineColor = num;
        }

        public final void setLineDash(List<Float> list) {
            this.lineDash = list;
        }

        public final void setLineWidth(Float f10) {
            this.lineWidth = f10;
        }

        public final void setLocked(Boolean bool) {
            this.isLocked = bool;
        }

        public final void setPercentageList(List<PercentageCell> list) {
            this.percentageList = list;
        }

        public final void setShowBackground(Boolean bool) {
            this.showBackground = bool;
        }

        public String toString() {
            return "Options(isLocked=" + this.isLocked + ", lineWidth=" + this.lineWidth + ", lineColor=" + this.lineColor + ", background=" + this.background + ", showBackground=" + this.showBackground + ", lineDash=" + this.lineDash + ", fontText=" + this.fontText + ", fontSize=" + this.fontSize + ", fontWeight=" + this.fontWeight + ", fontColor=" + this.fontColor + ", fontWidth=" + this.fontWidth + ", percentageList=" + this.percentageList + ')';
        }
    }

    @Keep
    @Metadata(d1 = {"\u0000 \n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000b\n\u0000\n\u0002\u0010\u000e\n\u0002\b\f\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B\u0017\u0012\u0006\u0010\u0002\u001a\u00020\u0003\u0012\u0006\u0010\u0004\u001a\u00020\u0005¢\u0006\u0004\b\u0006\u0010\u0007J\t\u0010\f\u001a\u00020\u0003HÆ\u0003J\t\u0010\r\u001a\u00020\u0005HÆ\u0003J\u001d\u0010\u000e\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u0005HÆ\u0001J\u0013\u0010\u000f\u001a\u00020\u00032\b\u0010\u0010\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0011\u001a\u00020\u0012HÖ\u0001J\t\u0010\u0013\u001a\u00020\u0005HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\tR\u0011\u0010\u0004\u001a\u00020\u0005¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000b¨\u0006\u0014"}, d2 = {"Lsp/aicoin_kline/chart/data/drawing/DrawingItem$PercentageCell;", "", "display", "", "percentage", "", "<init>", "(ZLjava/lang/String;)V", "getDisplay", "()Z", "getPercentage", "()Ljava/lang/String;", "component1", "component2", "copy", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
    public static final /* data */ class PercentageCell {
        private final boolean display;
        private final String percentage;

        public PercentageCell(boolean z10, String str) {
            this.display = z10;
            this.percentage = str;
        }

        public static /* synthetic */ PercentageCell copy$default(PercentageCell percentageCell, boolean z10, String str, int i10, Object obj) {
            if ((i10 & 1) != 0) {
                z10 = percentageCell.display;
            }
            if ((i10 & 2) != 0) {
                str = percentageCell.percentage;
            }
            return percentageCell.copy(z10, str);
        }

        /* JADX INFO: renamed from: component1, reason: from getter */
        public final boolean getDisplay() {
            return this.display;
        }

        /* JADX INFO: renamed from: component2, reason: from getter */
        public final String getPercentage() {
            return this.percentage;
        }

        public final PercentageCell copy(boolean display, String percentage) {
            return new PercentageCell(display, percentage);
        }

        public boolean equals(Object other) {
            if (this == other) {
                return true;
            }
            if (!(other instanceof PercentageCell)) {
                return false;
            }
            PercentageCell percentageCell = (PercentageCell) other;
            return this.display == percentageCell.display && AbstractC7609s.f(this.percentage, percentageCell.percentage);
        }

        public final boolean getDisplay() {
            return this.display;
        }

        public final String getPercentage() {
            return this.percentage;
        }

        public int hashCode() {
            return this.percentage.hashCode() + (Boolean.hashCode(this.display) * 31);
        }

        public String toString() {
            StringBuilder sb2 = new StringBuilder("PercentageCell(display=");
            sb2.append(this.display);
            sb2.append(", percentage=");
            return h.a(sb2, this.percentage, ')');
        }
    }

    public DrawingItem(DrawingPoint[] drawingPointArr, String str, String str2, Options options, boolean z10, List<PointF> list) {
        this.points = drawingPointArr;
        this.name = str;
        this.id = str2;
        this.options = options;
        this.isSelected = z10;
        this.decisionPoints = list;
    }

    public /* synthetic */ DrawingItem(DrawingPoint[] drawingPointArr, String str, String str2, Options options, boolean z10, List list, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this(drawingPointArr, str, str2, options, (i10 & 16) != 0 ? false : z10, (i10 & 32) != 0 ? new ArrayList() : list);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ DrawingItem copy$default(DrawingItem drawingItem, DrawingPoint[] drawingPointArr, String str, String str2, Options options, boolean z10, List list, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            drawingPointArr = drawingItem.points;
        }
        if ((i10 & 2) != 0) {
            str = drawingItem.name;
        }
        if ((i10 & 4) != 0) {
            str2 = drawingItem.id;
        }
        if ((i10 & 8) != 0) {
            options = drawingItem.options;
        }
        if ((i10 & 16) != 0) {
            z10 = drawingItem.isSelected;
        }
        if ((i10 & 32) != 0) {
            list = drawingItem.decisionPoints;
        }
        boolean z11 = z10;
        List list2 = list;
        return drawingItem.copy(drawingPointArr, str, str2, options, z11, list2);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final DrawingPoint[] getPoints() {
        return this.points;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getName() {
        return this.name;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getId() {
        return this.id;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final Options getOptions() {
        return this.options;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final boolean getIsSelected() {
        return this.isSelected;
    }

    public final List<PointF> component6() {
        return this.decisionPoints;
    }

    public final DrawingItem copy(DrawingPoint[] points, String name, String id2, Options options, boolean isSelected, List<PointF> decisionPoints) {
        return new DrawingItem(points, name, id2, options, isSelected, decisionPoints);
    }

    public final void copyWith(DrawingItem targetItem) {
        this.points = targetItem.points;
        this.options = targetItem.options;
        this.isSelected = targetItem.isSelected;
        this.decisionPoints = targetItem.decisionPoints;
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof DrawingItem)) {
            return false;
        }
        DrawingItem drawingItem = (DrawingItem) other;
        return AbstractC7609s.f(this.points, drawingItem.points) && AbstractC7609s.f(this.name, drawingItem.name) && AbstractC7609s.f(this.id, drawingItem.id) && AbstractC7609s.f(this.options, drawingItem.options) && this.isSelected == drawingItem.isSelected && AbstractC7609s.f(this.decisionPoints, drawingItem.decisionPoints);
    }

    public final List<PointF> getDecisionPoints() {
        return this.decisionPoints;
    }

    public final String getId() {
        return this.id;
    }

    public final String getName() {
        return this.name;
    }

    public final Options getOptions() {
        return this.options;
    }

    public final DrawingPoint[] getPoints() {
        return this.points;
    }

    public int hashCode() {
        int iA = d.a(this.id, d.a(this.name, Arrays.hashCode(this.points) * 31, 31), 31);
        Options options = this.options;
        return this.decisionPoints.hashCode() + ((Boolean.hashCode(this.isSelected) + ((iA + (options == null ? 0 : options.hashCode())) * 31)) * 31);
    }

    public final boolean isSelected() {
        return this.isSelected;
    }

    public final void setDecisionPoints(List<PointF> list) {
        this.decisionPoints = list;
    }

    public final void setId(String str) {
        this.id = str;
    }

    public final void setOptions(Options options) {
        this.options = options;
    }

    public final void setPoints(DrawingPoint[] drawingPointArr) {
        this.points = drawingPointArr;
    }

    public final void setSelected(boolean z10) {
        this.isSelected = z10;
    }

    public String toString() {
        return "DrawingItem(points=" + Arrays.toString(this.points) + ", name=" + this.name + ", id=" + this.id + ", options=" + this.options + ", isSelected=" + this.isSelected + ", decisionPoints=" + this.decisionPoints + ')';
    }
}
