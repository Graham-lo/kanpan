package gk;

import Rj.C2732n;
import Sf.AbstractC2803q;
import java.util.List;
import org.apache.tika.mime.MimeTypesReaderMetKeys;

/* JADX INFO: loaded from: classes7.dex */
public final class Z extends W {
    public Z(C2732n c2732n, String str, sp.aicoin_kline.core.indicator.config.F f10) {
        super(c2732n, str, f10);
    }

    @Override // gk.W
    public String D() {
        return "fundflow";
    }

    @Override // gk.W
    public List E() {
        return AbstractC2803q.e(MimeTypesReaderMetKeys.MATCH_VALUE_ATTR);
    }
}
