package nk;

import android.graphics.Color;
import com.tencent.android.tpns.mqtt.MqttTopic;
import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/* JADX INFO: loaded from: classes7.dex */
public final class b {

    /* JADX INFO: renamed from: a, reason: collision with root package name */
    public static final b f134194a = new b();

    public static final int a(float f10, int i10) {
        return (Math.min(255, Math.max(0, (int) (f10 * 255))) << 24) + (i10 & 16777215);
    }

    public static final int b(String str) {
        if (!Ah.x.O(str, MqttTopic.MULTI_LEVEL_WILDCARD, false, 2, null)) {
            return 0;
        }
        int length = str.length();
        if (length != 4) {
            if (length == 7 || length == 9) {
                return Color.parseColor(str);
            }
            return 0;
        }
        StringBuilder sb2 = new StringBuilder(MqttTopic.MULTI_LEVEL_WILDCARD);
        for (int i10 = 0; i10 < 6; i10++) {
            sb2.append(str.charAt((i10 + 2) / 2));
        }
        return Color.parseColor(sb2.toString());
    }

    public static final int d(String str) {
        if (Ah.x.O(str, MqttTopic.MULTI_LEVEL_WILDCARD, false, 2, null)) {
            return b(str);
        }
        ArrayList arrayList = new ArrayList();
        Matcher matcher = Pattern.compile("(\\d?)+\\d\\.?(\\d?)+").matcher(str);
        while (matcher.find()) {
            String strGroup = matcher.group();
            Double dN = Ah.v.n((strGroup == null || strGroup.length() == 0) ? "0" : matcher.group());
            arrayList.add(Double.valueOf(dN != null ? dN.doubleValue() : 0.0d));
        }
        if (arrayList.size() == 3) {
            return Color.argb(255, (int) ((Number) arrayList.get(0)).doubleValue(), (int) ((Number) arrayList.get(1)).doubleValue(), (int) ((Number) arrayList.get(2)).doubleValue());
        }
        return arrayList.size() == 4 ? Color.argb((int) (((Number) arrayList.get(3)).doubleValue() * ((double) 255)), (int) ((Number) arrayList.get(0)).doubleValue(), (int) ((Number) arrayList.get(1)).doubleValue(), (int) ((Number) arrayList.get(2)).doubleValue()) : Color.argb(0, 0, 0, 0);
    }

    public final String c(Integer num) {
        if (num == null) {
            return null;
        }
        float fIntValue = (num.intValue() >>> 24) / 255;
        return "rgba(" + ((num.intValue() & 16711680) >> 16) + ',' + ((num.intValue() & 65280) >> 8) + ',' + (num.intValue() & 255) + ',' + fIntValue + ')';
    }
}
