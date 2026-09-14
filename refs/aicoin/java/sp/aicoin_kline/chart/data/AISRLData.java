package sp.aicoin_kline.chart.data;

import Sf.AbstractC2804s;
import Sf.z;
import androidx.annotation.Keep;
import com.umeng.analytics.pro.am;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import kk.h;
import kotlin.Metadata;
import kotlin.jvm.internal.DefaultConstructorMarker;
import p167hg.AbstractC7609s;
import p254m.aicoin.kline.main.MainKlineFragment;

/* JADX INFO: loaded from: classes7.dex */
@Keep
@Metadata(d1 = {"\u00004\n\u0002\u0018\u0002\n\u0002\u0010\u0000\n\u0002\u0010!\n\u0002\u0018\u0002\n\u0002\b\u0002\n\u0002\u0010\u000e\n\u0002\b\u0003\n\u0002\u0018\u0002\n\u0002\b\u000e\n\u0002\u0010\b\n\u0002\b\u0003\n\u0002\u0010\u000b\n\u0002\b\u000f\b\u0087\b\u0018\u0000 *2\u00020\u0001:\u0001+B1\u0012\u000e\b\u0002\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002\u0012\u000e\b\u0002\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002\u0012\b\b\u0002\u0010\u0007\u001a\u00020\u0006¢\u0006\u0004\b\b\u0010\tJ\r\u0010\u000b\u001a\u00020\n¢\u0006\u0004\b\u000b\u0010\fJ\u0015\u0010\u000e\u001a\u00020\n2\u0006\u0010\r\u001a\u00020\u0000¢\u0006\u0004\b\u000e\u0010\u000fJ\r\u0010\u0010\u001a\u00020\u0000¢\u0006\u0004\b\u0010\u0010\u0011J\u0016\u0010\u0012\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002HÆ\u0003¢\u0006\u0004\b\u0012\u0010\u0013J\u0016\u0010\u0014\u001a\b\u0012\u0004\u0012\u00020\u00030\u0002HÆ\u0003¢\u0006\u0004\b\u0014\u0010\u0013J\u0010\u0010\u0015\u001a\u00020\u0006HÆ\u0003¢\u0006\u0004\b\u0015\u0010\u0016J:\u0010\u000e\u001a\u00020\u00002\u000e\b\u0002\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00022\u000e\b\u0002\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00030\u00022\b\b\u0002\u0010\u0007\u001a\u00020\u0006HÆ\u0001¢\u0006\u0004\b\u000e\u0010\u0017J\u0010\u0010\u0018\u001a\u00020\u0006HÖ\u0001¢\u0006\u0004\b\u0018\u0010\u0016J\u0010\u0010\u001a\u001a\u00020\u0019HÖ\u0001¢\u0006\u0004\b\u001a\u0010\u001bJ\u001a\u0010\u001e\u001a\u00020\u001d2\b\u0010\u001c\u001a\u0004\u0018\u00010\u0001HÖ\u0003¢\u0006\u0004\b\u001e\u0010\u001fR(\u0010\u0004\u001a\b\u0012\u0004\u0012\u00020\u00030\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0004\u0010 \u001a\u0004\b!\u0010\u0013\"\u0004\b\"\u0010#R(\u0010\u0005\u001a\b\u0012\u0004\u0012\u00020\u00030\u00028\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0005\u0010 \u001a\u0004\b$\u0010\u0013\"\u0004\b%\u0010#R\"\u0010\u0007\u001a\u00020\u00068\u0006@\u0006X\u0086\u000e¢\u0006\u0012\n\u0004\b\u0007\u0010&\u001a\u0004\b'\u0010\u0016\"\u0004\b(\u0010)¨\u0006,"}, d2 = {"Lsp/aicoin_kline/chart/data/AISRLData;", "", "", "Lsp/aicoin_kline/chart/data/AISRLItem;", "askList", "bidList", "", MainKlineFragment.FIELD_AISRL_AMOUNT_UNIT, "<init>", "(Ljava/util/List;Ljava/util/List;Ljava/lang/String;)V", "LQf/H;", "clear", "()V", "data", "copy", "(Lsp/aicoin_kline/chart/data/AISRLData;)V", "deepCopy", "()Lsp/aicoin_kline/chart/data/AISRLData;", "component1", "()Ljava/util/List;", "component2", "component3", "()Ljava/lang/String;", "(Ljava/util/List;Ljava/util/List;Ljava/lang/String;)Lsp/aicoin_kline/chart/data/AISRLData;", "toString", "", "hashCode", "()I", "other", "", "equals", "(Ljava/lang/Object;)Z", "Ljava/util/List;", "getAskList", "setAskList", "(Ljava/util/List;)V", "getBidList", "setBidList", "Ljava/lang/String;", "getAmountUnit", MainKlineFragment.METHOD_SET_AISRL_AMOUNT_UNIT, "(Ljava/lang/String;)V", "Companion", am.av, "lib_release"}, k = 1, mv = {2, 0, 0}, xi = 48)
public final /* data */ class AISRLData {
    public static final String DEFAULT_AMOUNT_UNIT = "张";
    private String amountUnit;
    private List<AISRLItem> askList;
    private List<AISRLItem> bidList;

    public AISRLData() {
        this(null, null, null, 7, null);
    }

    public AISRLData(List<AISRLItem> list, List<AISRLItem> list2, String str) {
        this.askList = list;
        this.bidList = list2;
        this.amountUnit = str;
    }

    public /* synthetic */ AISRLData(List list, List list2, String str, int i10, DefaultConstructorMarker defaultConstructorMarker) {
        this((i10 & 1) != 0 ? new ArrayList() : list, (i10 & 2) != 0 ? new ArrayList() : list2, (i10 & 4) != 0 ? "" : str);
    }

    /* JADX WARN: Multi-variable type inference failed */
    public static /* synthetic */ AISRLData copy$default(AISRLData aISRLData, List list, List list2, String str, int i10, Object obj) {
        if ((i10 & 1) != 0) {
            list = aISRLData.askList;
        }
        if ((i10 & 2) != 0) {
            list2 = aISRLData.bidList;
        }
        if ((i10 & 4) != 0) {
            str = aISRLData.amountUnit;
        }
        return aISRLData.copy(list, list2, str);
    }

    public final void clear() {
        this.askList.clear();
        this.bidList.clear();
        this.amountUnit = "";
    }

    public final List<AISRLItem> component1() {
        return this.askList;
    }

    public final List<AISRLItem> component2() {
        return this.bidList;
    }

    /* JADX INFO: renamed from: component3, reason: from getter */
    public final String getAmountUnit() {
        return this.amountUnit;
    }

    public final AISRLData copy(List<AISRLItem> askList, List<AISRLItem> bidList, String amountUnit) {
        return new AISRLData(askList, bidList, amountUnit);
    }

    public final void copy(AISRLData data) {
        List<AISRLItem> list = data.askList;
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(list, 10));
        Iterator<T> it = list.iterator();
        while (it.hasNext()) {
            arrayList.add(AISRLItem.copy$default((AISRLItem) it.next(), 0.0d, 0.0d, null, 0, 15, null));
        }
        this.askList = z.u1(arrayList);
        List<AISRLItem> list2 = data.bidList;
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(list2, 10));
        Iterator<T> it2 = list2.iterator();
        while (it2.hasNext()) {
            arrayList2.add(AISRLItem.copy$default((AISRLItem) it2.next(), 0.0d, 0.0d, null, 0, 15, null));
        }
        this.bidList = z.u1(arrayList2);
        this.amountUnit = data.amountUnit;
    }

    public final AISRLData deepCopy() {
        List<AISRLItem> list = this.askList;
        ArrayList arrayList = new ArrayList(AbstractC2804s.y(list, 10));
        Iterator<T> it = list.iterator();
        while (it.hasNext()) {
            arrayList.add(AISRLItem.copy$default((AISRLItem) it.next(), 0.0d, 0.0d, null, 0, 15, null));
        }
        List listU1 = z.u1(arrayList);
        List<AISRLItem> list2 = this.bidList;
        ArrayList arrayList2 = new ArrayList(AbstractC2804s.y(list2, 10));
        Iterator<T> it2 = list2.iterator();
        while (it2.hasNext()) {
            arrayList2.add(AISRLItem.copy$default((AISRLItem) it2.next(), 0.0d, 0.0d, null, 0, 15, null));
        }
        return new AISRLData(listU1, z.u1(arrayList2), this.amountUnit);
    }

    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof AISRLData)) {
            return false;
        }
        AISRLData aISRLData = (AISRLData) other;
        return AbstractC7609s.f(this.askList, aISRLData.askList) && AbstractC7609s.f(this.bidList, aISRLData.bidList) && AbstractC7609s.f(this.amountUnit, aISRLData.amountUnit);
    }

    public final String getAmountUnit() {
        return this.amountUnit;
    }

    public final List<AISRLItem> getAskList() {
        return this.askList;
    }

    public final List<AISRLItem> getBidList() {
        return this.bidList;
    }

    public int hashCode() {
        return this.amountUnit.hashCode() + ((this.bidList.hashCode() + (this.askList.hashCode() * 31)) * 31);
    }

    public final void setAmountUnit(String str) {
        this.amountUnit = str;
    }

    public final void setAskList(List<AISRLItem> list) {
        this.askList = list;
    }

    public final void setBidList(List<AISRLItem> list) {
        this.bidList = list;
    }

    public String toString() {
        StringBuilder sb2 = new StringBuilder("AISRLData(askList=");
        sb2.append(this.askList);
        sb2.append(", bidList=");
        sb2.append(this.bidList);
        sb2.append(", amountUnit=");
        return h.a(sb2, this.amountUnit, ')');
    }
}
