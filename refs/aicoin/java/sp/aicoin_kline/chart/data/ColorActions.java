package sp.aicoin_kline.chart.data;

import androidx.annotation.Keep;
import com.tencent.android.tpush.common.MessageKey;
import java.util.Map;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import org.apache.tika.mime.MimeTypesReaderMetKeys;
import p167hg.AbstractC7609s;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u0000(\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0000\n\u0002\u0010\u000e\n\u0000\n\u0002\u0010$\n\u0002\b\n\n\u0002\u0010\u000b\n\u0002\b\u0002\n\u0002\u0010\b\n\u0002\b\u0002\b\u0087\b\u0018\u00002\u00020\u0001B%\u0012\b\b\u0002\u0010\u0002\u001a\u00020\u0003\u0012\u0012\u0010\u0004\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\u0005¢\u0006\u0004\b\u0006\u0010\u0007J\t\u0010\f\u001a\u00020\u0003HÆ\u0003J\u0015\u0010\r\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\u0005HÆ\u0003J)\u0010\u000e\u001a\u00020\u00002\b\b\u0002\u0010\u0002\u001a\u00020\u00032\u0014\b\u0002\u0010\u0004\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\u0005HÆ\u0001J\u0013\u0010\u000f\u001a\u00020\u00102\b\u0010\u0011\u001a\u0004\u0018\u00010\u0001HÖ\u0003J\t\u0010\u0012\u001a\u00020\u0013HÖ\u0001J\t\u0010\u0014\u001a\u00020\u0003HÖ\u0001R\u0011\u0010\u0002\u001a\u00020\u0003¢\u0006\b\n\u0000\u001a\u0004\b\b\u0010\tR\u001d\u0010\u0004\u001a\u000e\u0012\u0004\u0012\u00020\u0003\u0012\u0004\u0012\u00020\u00030\u0005¢\u0006\b\n\u0000\u001a\u0004\b\n\u0010\u000b¨\u0006\u0015"}, d2 = {"Lsp/aicoin_kline/chart/data/ColorActions;", "", MessageKey.NOTIFICATION_COLOR, "", MimeTypesReaderMetKeys.MATCH_VALUE_ATTR, "", "<init>", "(Ljava/lang/String;Ljava/util/Map;)V", "getColor", "()Ljava/lang/String;", "getValue", "()Ljava/util/Map;", "component1", "component2", "copy", "equals", "", "other", "hashCode", "", "toString", "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class ColorActions {
    private final String color;
    private final Map<String, String> value;

    public ColorActions(String str, Map<String, String> map) {
        this.color = str;
        this.value = map;
    }

    public /* synthetic */ ColorActions(String str, Map map, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? "" : str, map);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ ColorActions copy$default(ColorActions colorActions, String str, Map map, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            str = colorActions.color;
        }
        if ((i10 & 2) != 0) {
            map = colorActions.value;
        }
        return colorActions.copy(str, map);
    }

    /* JADX INFO: renamed from: component1, reason: from getter */
    public final String getColor() {
        return this.color;
    }

    public final Map<String, String> component2() {
        return this.value;
    }

    public final ColorActions copy(String color, Map<String, String> value) {
        return new ColorActions(color, value);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof ColorActions)) {
            return false;
        }
        ColorActions colorActions = (ColorActions) other;
        return AbstractC7609s.f(this.color, colorActions.color) && AbstractC7609s.f(this.value, colorActions.value);
    }

    public final String getColor() {
        return this.color;
    }

    public final Map<String, String> getValue() {
        return this.value;
    }

    public int hashCode() {
        return this.value.hashCode() + (this.color.hashCode() * 31);
    }

    public String toString() {
        return "ColorActions(color=" + this.color + ", value=" + this.value + ')';
    }
}
