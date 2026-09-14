package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.tencent.android.tpush.common.MessageKey;
import java.util.List;
import kk.a;
import kk.d;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00000\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0002\b\u0004\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\u0007\n\u0000\n\u0002\u0010 \n\u0002\b.\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B\u0091\u0001\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0004\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0005\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0006\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u0007\u001a\u00020\b\u0012\b\b\u0002\u0010\t\u001a\u00020\u0003\u0012\b\b\u0002\u0010\n\u001a\u00020\u000b\u0012\f\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00030\r\u0012\b\b\u0002\u0010\u000e\u001a\u00020\u0003\u0012\b\b\u0002\u0010\u000f\u001a\u00020\u000b\u0012\b\b\u0002\u0010\u0010\u001a\u00020\u0003\u0012\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u0003\u0012\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0003¢\u0006\u0004\b\u0013\u0010\u0014J\t\u0010+\u001a\u00020\u0003HÆ\u0003J\t\u0010,\u001a\u00020\u0003HÆ\u0003J\t\u0010-\u001a\u00020\u0003HÆ\u0003J\t\u0010.\u001a\u00020\u0003HÆ\u0003J\t\u0010/\u001a\u00020\bHÆ\u0003J\t\u00100\u001a\u00020\u0003HÆ\u0003J\t\u00101\u001a\u00020\u000bHÆ\u0003J\u000f\u00102\u001a\b\u0012\u0004\u0012\u00020\u00030\rHÆ\u0003J\t\u00103\u001a\u00020\u0003HÆ\u0003J\t\u00104\u001a\u00020\u000bHÆ\u0003J\t\u00105\u001a\u00020\u0003HÆ\u0003J\u000b\u00106\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u000b\u00107\u001a\u0004\u0018\u00010\u0003HÆ\u0003J\u0095\u0001\u00108\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\b\b\u0002\u0010\u0004\u001a\u00020\u00032\b\b\u0002\u0010\u0005\u001a\u00020\u00032\b\b\u0002\u0010\u0006\u001a\u00020\u00032\b\b\u0002\u0010\u0007\u001a\u00020\b2\b\b\u0002\u0010\t\u001a\u00020\u00032\b\b\u0002\u0010\n\u001a\u00020\u000b2\u000e\b\u0002\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00030\r2\b\b\u0002\u0010\u000e\u001a\u00020\u00032\b\b\u0002\u0010\u000f\u001a\u00020\u000b2\b\b\u0002\u0010\u0010\u001a\u00020\u00032\n\b\u0002\u0010\u0011\u001a\u0004\u0018\u00010\u00032\n\b\u0002\u0010\u0012\u001a\u0004\u0018\u00010\u0003HÆ\u0001J\u0013\u00109\u001a\u00020\b2\b\u0010:\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010;\u001a\u00020<HÖ\u0001J\t\u0010=\u001a\u00020\u0003HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0015\u0010\u0016R\u0011\u0010\u0004\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0017\u0010\u0016R\u0011\u0010\u0005\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0018\u0010\u0016R\u0011\u0010\u0006\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u0019\u0010\u0016R\u001a\u0010\u0007\u001a\u00020\bX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001a\u0010\u001b\"\u0004\b\u001c\u0010\u001dR\u0011\u0010\t\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\u001e\u0010\u0016R\u001a\u0010\n\u001a\u00020\u000bX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b\u001f\u0010 \"\u0004\b!\u0010\"R\u0017\u0010\f\u001a\b\u0012\u0004\u0012\u00020\u00030\r¢\u0006\b\n\u0000\u001a\u0004\b#\u0010$R\u0011\u0010\u000e\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b%\u0010\u0016R\u001a\u0010\u000f\u001a\u00020\u000bX\u0086\u000e¢\u0006\u000e\n\u0000\u001a\u0004\b&\u0010 \"\u0004\b'\u0010\"R\u0011\u0010\u0010\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b(\u0010\u0016R\u0013\u0010\u0011\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b)\u0010\u0016R\u0013\u0010\u0012\u001a\u0004\u0018\u00010\u0003¢\u0006\b\n\u0000\u001a\u0004\b*\u0010\u0016¨\u0006>"}, d2 = {"Lsp/aicoin_kline/chart/data/ActionOutput;", "", MessageKey.NOTIFICATION_COLOR, "", "placement", "shape", "text", "fill", "", "lineWidth", "floatLineWidth", "", "lineDash", "", "fontSize", "floatFontSize", "bgColor", "borderColor", "wickColor", "<init>", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZLjava/lang/String;FLjava/util/List;Ljava/lang/String;FLjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V", "getColor", "()Ljava/lang/String;", "getPlacement", "getShape", "getText", "getFill", "()Z", "setFill", "(Z)V", "getLineWidth", "getFloatLineWidth", "()F", "setFloatLineWidth", "(F)V", "getLineDash", "()Ljava/util/List;", "getFontSize", "getFloatFontSize", "setFloatFontSize", "getBgColor", "getBorderColor", "getWickColor", "component1", "component2", "component3", "component4", "component5", "component6", "component7", "component8", "component9", "component10", "component11", "component12", "component13", "copy", "equals", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ActionOutput {
    private final String bgColor;
    private final String borderColor;
    private final String color;
    private boolean fill;
    private float floatFontSize;
    private float floatLineWidth;
    private final String fontSize;
    private final List<String> lineDash;
    private final String lineWidth;
    private final String placement;
    private final String shape;
    private final String text;
    private final String wickColor;

    public ActionOutput(String str, String str2, String str3, String str4, boolean z10, String str5, float f10, List<String> list, String str6, float f11, String str7, String str8, String str9) {
        this.color = str;
        this.placement = str2;
        this.shape = str3;
        this.text = str4;
        this.fill = z10;
        this.lineWidth = str5;
        this.floatLineWidth = f10;
        this.lineDash = list;
        this.fontSize = str6;
        this.floatFontSize = f11;
        this.bgColor = str7;
        this.borderColor = str8;
        this.wickColor = str9;
    }

    public /* synthetic */ ActionOutput(String str, String str2, String str3, String str4, boolean z10, String str5, float f10, List list, String str6, float f11, String str7, String str8, String str9, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? "" : str, (i10 & 2) != 0 ? "" : str2, (i10 & 4) != 0 ? "" : str3, (i10 & 8) != 0 ? "" : str4, (i10 & 16) != 0 ? false : z10, (i10 & 32) != 0 ? "0" : str5, (i10 & 64) != 0 ? 2.0f : f10, list, (i10 & 256) != 0 ? "" : str6, (i10 & 512) != 0 ? 9.0f : f11, (i10 & 1024) != 0 ? "" : str7, (i10 & 2048) != 0 ? "" : str8, (i10 & 4096) != 0 ? "" : str9);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ ActionOutput copy$default(ActionOutput actionOutput, String str, String str2, String str3, String str4, boolean z10, String str5, float f10, List list, String str6, float f11, String str7, String str8, String str9, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = actionOutput.color;
        }
        return actionOutput.copy(str, (i10 & 2) != 0 ? actionOutput.placement : str2, (i10 & 4) != 0 ? actionOutput.shape : str3, (i10 & 8) != 0 ? actionOutput.text : str4, (i10 & 16) != 0 ? actionOutput.fill : z10, (i10 & 32) != 0 ? actionOutput.lineWidth : str5, (i10 & 64) != 0 ? actionOutput.floatLineWidth : f10, (i10 & 128) != 0 ? actionOutput.lineDash : list, (i10 & 256) != 0 ? actionOutput.fontSize : str6, (i10 & 512) != 0 ? actionOutput.floatFontSize : f11, (i10 & 1024) != 0 ? actionOutput.bgColor : str7, (i10 & 2048) != 0 ? actionOutput.borderColor : str8, (i10 & 4096) != 0 ? actionOutput.wickColor : str9);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getColor() {
        return this.color;
    }

    /* JADX INFO: renamed from: component10, reason: from getter */
    public final float getFloatFontSize() {
        return this.floatFontSize;
    }

    /* JADX INFO: renamed from: component11, reason: from getter */
    public final String getBgColor() {
        return this.bgColor;
    }

    /* JADX INFO: renamed from: component12, reason: from getter */
    public final String getBorderColor() {
        return this.borderColor;
    }

    /* JADX INFO: renamed from: component13, reason: from getter */
    public final String getWickColor() {
        return this.wickColor;
    }

    /* JADX INFO: renamed from: component2, reason: from getter */
    public final String getPlacement() {
        return this.placement;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getShape() {
        return this.shape;
    }

    /* JADX INFO: renamed from: component4, reason: from getter */
    public final String getText() {
        return this.text;
    }

    /* JADX INFO: renamed from: component5, reason: from getter */
    public final boolean getFill() {
        return this.fill;
    }

    /* JADX INFO: renamed from: component6, reason: from getter */
    public final String getLineWidth() {
        return this.lineWidth;
    }

    /* JADX INFO: renamed from: component7, reason: from getter */
    public final float getFloatLineWidth() {
        return this.floatLineWidth;
    }

    public final List<String> component8() {
        return this.lineDash;
    }

    /* JADX INFO: renamed from: component9, reason: from getter */
    public final String getFontSize() {
        return this.fontSize;
    }

    public final ActionOutput copy(String color, String placement, String shape, String text, boolean fill, String lineWidth, float floatLineWidth, List<String> lineDash, String fontSize, float floatFontSize, String bgColor, String borderColor, String wickColor) {
        return new ActionOutput(color, placement, shape, text, fill, lineWidth, floatLineWidth, lineDash, fontSize, floatFontSize, bgColor, borderColor, wickColor);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ActionOutput)) {
            return false;
        }
        ActionOutput actionOutput = (ActionOutput) other;
        return AbstractC7609s.f(this.color, actionOutput.color) && AbstractC7609s.f(this.placement, actionOutput.placement) && AbstractC7609s.f(this.shape, actionOutput.shape) && AbstractC7609s.f(this.text, actionOutput.text) && this.fill == actionOutput.fill && AbstractC7609s.f(this.lineWidth, actionOutput.lineWidth) && Float.compare(this.floatLineWidth, actionOutput.floatLineWidth) == 0 && AbstractC7609s.f(this.lineDash, actionOutput.lineDash) && AbstractC7609s.f(this.fontSize, actionOutput.fontSize) && Float.compare(this.floatFontSize, actionOutput.floatFontSize) == 0 && AbstractC7609s.f(this.bgColor, actionOutput.bgColor) && AbstractC7609s.f(this.borderColor, actionOutput.borderColor) && AbstractC7609s.f(this.wickColor, actionOutput.wickColor);
    }

    public final String getBgColor() {
        return this.bgColor;
    }

    public final String getBorderColor() {
        return this.borderColor;
    }

    public final String getColor() {
        return this.color;
    }

    public final boolean getFill() {
        return this.fill;
    }

    public final float getFloatFontSize() {
        return this.floatFontSize;
    }

    public final float getFloatLineWidth() {
        return this.floatLineWidth;
    }

    public final String getFontSize() {
        return this.fontSize;
    }

    public final List<String> getLineDash() {
        return this.lineDash;
    }

    public final String getLineWidth() {
        return this.lineWidth;
    }

    public final String getPlacement() {
        return this.placement;
    }

    public final String getShape() {
        return this.shape;
    }

    public final String getText() {
        return this.text;
    }

    public final String getWickColor() {
        return this.wickColor;
    }

    public int hashCode() {
        int iA = d.a(this.bgColor, a.a(this.floatFontSize, d.a(this.fontSize, (this.lineDash.hashCode() + a.a(this.floatLineWidth, d.a(this.lineWidth, (Boolean.hashCode(this.fill) + d.a(this.text, d.a(this.shape, d.a(this.placement, this.color.hashCode() * 31, 31), 31), 31)) * 31, 31), 31)) * 31, 31), 31), 31);
        String str = this.borderColor;
        int iHashCode = (iA + (str == null ? 0 : str.hashCode())) * 31;
        String str2 = this.wickColor;
        return iHashCode + (str2 != null ? str2.hashCode() : 0);
    }

    public final void setFill(boolean z10) {
        this.fill = z10;
    }

    public final void setFloatFontSize(float f10) {
        this.floatFontSize = f10;
    }

    public final void setFloatLineWidth(float f10) {
        this.floatLineWidth = f10;
    }

    public String toString() {
        return "ActionOutput(color=" + this.color + ", placement=" + this.placement + ", shape=" + this.shape + ", text=" + this.text + ", fill=" + this.fill + ", lineWidth=" + this.lineWidth + ", floatLineWidth=" + this.floatLineWidth + ", lineDash=" + this.lineDash + ", fontSize=" + this.fontSize + ", floatFontSize=" + this.floatFontSize + ", bgColor=" + this.bgColor + ", borderColor=" + this.borderColor + ", wickColor=" + this.wickColor + ')';
    }
}
